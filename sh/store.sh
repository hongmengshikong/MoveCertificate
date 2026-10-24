#!/system/bin/sh
# shellcheck shell=sh
# ============================================================================
# MoveCertificate - 证书仓库（合并证书库）
# ----------------------------------------------------------------------------
# 背景（Flutter 抓不到包的根因）：
#   1. Android 14+ 的系统证书在 /apex/com.android.conscrypt/cacerts，
#      /system/etc/security/cacerts 还保留一份（PEM 格式）。
#   2. 设置里安装的用户证书在 /data/misc/user/<id>/cacerts-added/，
#      文件名是 <hash>.0，但内容是 **DER**（见 AOSP TrustedCertificateStore
#      writeCertificate(): os.write(cert.getEncoded())）。
#   3. Flutter/Dart 的 libflutter.so 里内嵌 BoringSSL，Dart 的
#      security_context_linux.cc 通过
#          SSL_CTX_load_verify_locations(ctx, NULL, <证书目录>)
#      使用 hash 目录读取根证书。BoringSSL 的 by_dir 用
#          X509_LOOKUP_add_dir(dir, X509_FILETYPE_PEM)
#      注册目录，也就是说：
#          - 文件名必须是 <subject_hash>.0 / <subject_hash_old>.0
#          - 文件内容必须是 **PEM**
#      DER 会被静默跳过（无法解析 -> 当作没有这张 CA）。
#   => 所以本模块把「系统证书 + 用户证书 + 自定义证书」合并成一份仓库，
#      统一转成 PEM，再发布到系统证书目录 / APEX 目录。
# ============================================================================

# ==================== 编码判断 / 转换 ====================

# 是否 PEM 证书（以 "-----BEGIN " 开头）
cert_is_pem() {
    [ -f "$1" ] || return 1
    [ "$(head -c 11 "$1" 2>/dev/null)" = "-----BEGIN " ]
}

# 是否 DER 证书（ASN.1 SEQUENCE 以 0x30 开头）
cert_is_der() {
    [ -f "$1" ] || return 1
    [ "$(head -c 1 "$1" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')" = "30" ]
}

# DER -> PEM；$1 输入，$2 输出
cert_der_to_pem() {
    local in="$1" out="$2" b64
    command -v base64 >/dev/null 2>&1 || return 1
    b64=$(base64 <"$in" 2>/dev/null | tr -d '\r\n')
    [ -n "$b64" ] || return 1
    {
        echo "-----BEGIN CERTIFICATE-----"
        printf '%s' "$b64" | awk '{ s=$0; while (length(s) > 64) { print substr(s, 1, 64); s = substr(s, 65) } if (length(s) > 0) print s }'
        echo "-----END CERTIFICATE-----"
    } >"$out" 2>/dev/null || return 1
    [ -s "$out" ] || return 1
    return 0
}

# 取出证书体的 base64（用于判断两个文件是不是同一张证书）
cert_body_b64() {
    if cert_is_pem "$1"; then
        sed '/^-----/d' "$1" 2>/dev/null | tr -d '\r\n'
    elif cert_is_der "$1"; then
        base64 <"$1" 2>/dev/null | tr -d '\r\n'
    fi
}

# 文件名是否为 Android 证书命名规范：<8位十六进制 hash>.<序号>
cert_name_is_hash() {
    case "$1" in
        [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F].*)
            return 0
            ;;
    esac
    return 1
}

# 用 openssl 计算 Android 使用的 hash 名（设备上一般没有 openssl）
cert_hash_by_openssl() {
    command -v openssl >/dev/null 2>&1 || return 1
    local h=""
    if cert_is_pem "$1"; then
        h=$(openssl x509 -in "$1" -noout -subject_hash_old 2>/dev/null)
    else
        h=$(openssl x509 -inform der -in "$1" -noout -subject_hash_old 2>/dev/null)
    fi
    [ -n "$h" ] || return 1
    echo "$h"
}

# 在仓库里找一张内容相同、且文件名合法的证书，借用它的名字
cert_hash_by_body() {
    local body f b
    body=$(cert_body_b64 "$1")
    [ -n "$body" ] || return 1
    for f in "$MODULE_CERT_DIR"/*; do
        [ -f "$f" ] || continue
        b=${f##*/}
        cert_name_is_hash "$b" || continue
        [ "$(cert_body_b64 "$f")" = "$body" ] || continue
        echo "$b"
        return 0
    done
    return 1
}

# 给一个证书文件找一个可用名字（hash 名），找不到返回空
# 幂等：如果 <hash>.0 已经存在且内容相同，直接复用（避免重复启动不断生成 .1/.2）
cert_resolve_name() {
    local src="$1" hash candidate n body
    hash=$(cert_hash_by_openssl "$src" 2>/dev/null)
    body=$(cert_body_b64 "$src")
    if [ -n "$hash" ]; then
        n=0
        while [ "$n" -le 20 ]; do
            candidate="$hash.$n"
            if [ ! -e "$CUSTOM_CERT_DIR/$candidate" ]; then
                echo "$candidate"
                return 0
            fi
            if [ -n "$body" ] && [ "$(cert_body_b64 "$CUSTOM_CERT_DIR/$candidate")" = "$body" ]; then
                echo "$candidate"
                return 0
            fi
            n=$((n + 1))
        done
        return 1
    fi
    cert_hash_by_body "$src" 2>/dev/null
}

# ==================== 仓库维护 ====================

store_count() {
    ls -1A "$MODULE_CERT_DIR" 2>/dev/null | wc -l | tr -d ' '
}

# 系统证书来源：Android 14+ 用 APEX，其它用 /system
store_system_source() {
    if [ "$sdk_version_number" -ge 34 ] && [ -d "$APEX_CONSCRYPT_DIR" ] &&
        [ -n "$(ls -A "$APEX_CONSCRYPT_DIR" 2>/dev/null)" ]; then
        echo "$APEX_CONSCRYPT_DIR"
    else
        echo "$SYSTEM_CERT_DIR"
    fi
}

store_seed_system() {
    local src
    src=$(store_system_source)
    print_log "seed store from $src"
    [ -d "$src" ] || return 1
    cp -f "$src"/* "$MODULE_CERT_DIR"/ 2>/dev/null
    print_log "store after system seed: $(store_count)"
    return 0
}

# 导入所有用户（含工作资料）安装的用户证书
store_import_users() {
    local d n
    for d in "$USER_CERT_ROOT"/*/cacerts-added; do
        [ -d "$d" ] || continue
        n=$(ls -1A "$d" 2>/dev/null | wc -l | tr -d ' ')
        [ "$n" -gt 0 ] || continue
        cp -f "$d"/* "$MODULE_CERT_DIR"/ 2>/dev/null
        print_log "import $(printf %s "$d") certs: $n"
    done
    return 0
}

# 导入 /data/local/tmp/cert 下的自定义证书
# 支持 PEM / DER；DER 会就地转成 PEM；文件名不是 <hash>.n 的会尽量自动重命名
store_import_custom() {
    [ -d "$CUSTOM_CERT_DIR" ] || {
        print_log "custom cert dir $CUSTOM_CERT_DIR not found (skip)"
        return 0
    }

    local f base tmp newname
    for f in "$CUSTOM_CERT_DIR"/*; do
        [ -f "$f" ] || continue
        base=${f##*/}
        case "$base" in
            .*) continue ;;
        esac

        tmp="$CUSTOM_CERT_DIR/.$base.tmp"
        cp -f "$f" "$tmp" 2>/dev/null || continue

        if cert_is_pem "$tmp"; then
            :
        elif cert_is_der "$tmp"; then
            if cert_der_to_pem "$tmp" "$tmp.pem"; then
                mv -f "$tmp.pem" "$tmp" 2>/dev/null
                print_log "custom cert $base: DER -> PEM"
            else
                print_log "custom cert $base: DER convert failed, skip"
                rm -f "$tmp"
                continue
            fi
        else
            print_log "custom cert $base: not a certificate (PEM/DER), ignored"
            rm -f "$tmp"
            continue
        fi

        if ! cert_name_is_hash "$base"; then
            newname=$(cert_resolve_name "$tmp" 2>/dev/null)
            if [ -n "$newname" ] && [ "$newname" != "$base" ]; then
                mv -f "$tmp" "$CUSTOM_CERT_DIR/$newname" 2>/dev/null
                cp -f "$CUSTOM_CERT_DIR/$newname" "$MODULE_CERT_DIR/$newname" 2>/dev/null
                # 真正重命名：删掉旧名字的文件，否则下次启动会重复导入
                rm -f "$f" 2>/dev/null
                print_log "custom cert $base: renamed to $newname (Flutter needs <hash>.0)"
                continue
            fi
            print_log "WARN: custom cert $base is not named <hash>.0."
            print_log "      Java/Conscrypt 能用；Flutter/Dart(libflutter.so) 只认 <subject_hash_old>.0，会忽略它。"
            print_log "      在电脑上执行: openssl x509 -in $base -noout -subject_hash_old  然后把文件改成 <hash>.0"
        fi

        mv -f "$tmp" "$CUSTOM_CERT_DIR/$base" 2>/dev/null
        cp -f "$CUSTOM_CERT_DIR/$base" "$MODULE_CERT_DIR/$base" 2>/dev/null
        print_log "custom cert $base: imported"
    done
    return 0
}

# 统一转成 PEM（DER 一律转换），并统计
store_normalize() {
    local f base tmp pem=0 conv=0 bad=0
    for f in "$MODULE_CERT_DIR"/*; do
        [ -f "$f" ] || continue
        base=${f##*/}
        case "$base" in
            .*|*tmp) continue ;;
        esac

        if cert_is_pem "$f"; then
            pem=$((pem + 1))
        elif cert_is_der "$f"; then
            tmp="$f.der2pem"
            if cert_der_to_pem "$f" "$tmp"; then
                mv -f "$tmp" "$f" 2>/dev/null
                pem=$((pem + 1))
                conv=$((conv + 1))
            else
                rm -f "$tmp"
                bad=$((bad + 1))
            fi
        else
            bad=$((bad + 1))
            # 仓库里只放证书；用户目录里的原文件不动
            rm -f "$f" 2>/dev/null
            print_log "cert store: $base is neither PEM nor DER, removed from store"
        fi
    done
    print_log "cert store encoding: pem=$pem converted_der=$conv invalid=$bad"
    return 0
}

# 组装合并证书仓库。返回 0 表示仓库可用。
prepare_cert_store() {
    mkdir -p -m 755 "$MODULE_CERT_DIR" 2>/dev/null || return 1
    mkdir -p -m 755 "$USER_CERT_DIR" 2>/dev/null
    mkdir -p -m 777 "$CUSTOM_CERT_DIR" 2>/dev/null

    store_seed_system
    store_import_users
    store_import_custom
    store_normalize

    # AdGuard 冲突证书清理 + 过期 conscrypt 目录清理
    compatible

    local count
    count=$(store_count)
    print_log "cert store total: $count"
    if [ "$count" -lt 20 ]; then
        print_log "FATAL: cert store has only $count certs, refuse to publish (system CA keeps untouched)"
        return 1
    fi
    return 0
}

# ==================== 发布 ====================

# 把仓库同步到目标目录（并清掉目标目录里仓库已删除的旧文件）
# $1 目标目录  $2 system|apex（决定属主/权限）
store_sync_to() {
    local dest="$1"
    local mode="${2:-system}"
    local f b

    mkdir -p -m 755 "$dest" 2>/dev/null || return 1

    for f in "$dest"/*; do
        [ -f "$f" ] || continue
        b=${f##*/}
        [ -f "$MODULE_CERT_DIR/$b" ] || rm -f "$f" 2>/dev/null
    done

    cp -f "$MODULE_CERT_DIR"/* "$dest"/ 2>/dev/null

    case "$mode" in
        apex) fix_system_permissions14 "$dest" ;;
        *) fix_system_permissions "$dest" ;;
    esac
    return 0
}

# 选一张“用户证书”作为探针，用来判断某个目录里到底有没有我们的证书。
# 探针必须来自**用户证书目录 / 自定义证书目录**（这两处不会被模块改动），
# 不能用 system_certs.txt 判断——如果脚本在模块已经挂载之后执行，
# 那份列表里会混进用户证书，导致永远找不到探针。
pick_store_probe() {
    STORE_PROBE=""
    local d f b
    for d in "$USER_CERT_ROOT"/*/cacerts-added "$CUSTOM_CERT_DIR"; do
        [ -d "$d" ] || continue
        for f in "$d"/*; do
            [ -f "$f" ] || continue
            b=${f##*/}
            cert_name_is_hash "$b" || continue
            [ -f "$MODULE_CERT_DIR/$b" ] || continue
            STORE_PROBE="$b"
            return 0
        done
    done
    return 1
}

# 目标目录是否已经和仓库完全一致（精确判断，用于 legacy /system 路径）
dir_matches_store() {
    local dir="$1" f b
    [ -d "$dir" ] || return 1
    for f in "$MODULE_CERT_DIR"/*; do
        [ -f "$f" ] || continue
        b=${f##*/}
        [ -f "$dir/$b" ] || return 1
    done
    return 0
}

# 返回 $1 处的挂载 root（mountinfo 第 4 列），没有挂载返回空
mount_root_at() {
    awk -v t="$1" '$5 == t { print $4; exit }' /proc/self/mountinfo 2>/dev/null
}

# 卸载"我们自己之前挂在 $1 上的那一层"。
# 只处理 root != "/" 的 bind 挂载，绝不 umount ROM 自己的整盘挂载。
clear_our_mount() {
    local tgt="$1" root
    root=$(mount_root_at "$tgt")
    [ -n "$root" ] || return 0
    [ "$root" = "/" ] && return 1
    umount "$tgt" 2>/dev/null
    print_log "umount previous mount on $tgt status:$?"
    return 0
}

# ==================== /system/etc/security/cacerts ====================
# 关键修复：Flutter/Dart 的 BoringSSL 读的就是这个老路径
# （只有当 /apex/com.android.conscrypt/cacerts 不存在时，
#   新版 Dart 才会回退到它；老版 Flutter 则只读它）
install_legacy_store() {
    local allow_mount="${1:-1}"
    local probe

    print_log "install legacy store -> $MODULE_SYSTEM_CERT_DIR"
    store_sync_to "$MODULE_SYSTEM_CERT_DIR" system
    set_selinux_context "$SYSTEM_CERT_DIR" "$MODULE_SYSTEM_CERT_DIR"

    if dir_matches_store "$SYSTEM_CERT_DIR"; then
        print_log "legacy store OK: $SYSTEM_CERT_DIR matches cert store (overlay effective)"
        return 0
    fi

    print_log "WARN: $SYSTEM_CERT_DIR does not match cert store (module overlay not applied?)"
    [ "$allow_mount" = "1" ] || return 1
    mount_legacy_store
}

# 兜底：模块 overlay 没生效时，直接把模块目录 bind 到 /system/etc/security/cacerts
mount_legacy_store() {
    local real root

    if [ ! -d "$SYSTEM_CERT_DIR" ]; then
        print_log "WARN: $SYSTEM_CERT_DIR does not exist, cannot bind legacy store"
        return 1
    fi

    if [ -L "$SYSTEM_CERT_DIR" ]; then
        real=$(readlink -f "$SYSTEM_CERT_DIR" 2>/dev/null)
        print_log "$SYSTEM_CERT_DIR is a symlink -> $real"
        case "$real" in
            /apex/com.android.conscrypt*)
                print_log "legacy path is covered by conscrypt apex mount, skip"
                return 0
                ;;
        esac
    fi

    root=$(mount_root_at "$SYSTEM_CERT_DIR")
    if [ -n "$root" ]; then
        if [ "$root" = "/" ]; then
            print_log "WARN: $SYSTEM_CERT_DIR is a whole-filesystem mount, refuse to umount"
            return 1
        fi
        clear_our_mount "$SYSTEM_CERT_DIR"
    fi

    mount -o bind "$MODULE_SYSTEM_CERT_DIR" "$SYSTEM_CERT_DIR" 2>/dev/null
    print_log "mount bind $MODULE_SYSTEM_CERT_DIR $SYSTEM_CERT_DIR status:$?"

    # 已经在运行的 init/zygote 也同步一份（post-fs-data 阶段一般还没有 zygote）
    local pid
    for pid in $(list_zygote_pids 2>/dev/null); do
        nsenter --mount="/proc/$pid/ns/mnt" -- /system/bin/mount -o bind "$MODULE_SYSTEM_CERT_DIR" "$SYSTEM_CERT_DIR" 2>/dev/null
        print_log "nsenter $pid bind legacy status:$?"
    done
    return 0
}

# ==================== /apex/com.android.conscrypt/cacerts ====================

# APEX 目录的“真实路径”。/apex/com.android.conscrypt 在新系统上是
# 指向 /apex/com.android.conscrypt@<ver> 的软链，mount 会解析到真实路径，
# 所以这里统一解析后再挂载/比较。
apex_install_targets() {
    local t r
    for t in "$APEX_CONSCRYPT_DIR" /apex/com.android.conscrypt@*/cacerts; do
        [ -e "$t" ] || continue
        r=$(readlink -f "$t" 2>/dev/null)
        [ -n "$r" ] || r="$t"
        echo "$r"
    done | sort -u
}

install_apex_store() {
    if [ ! -d "$APEX_CONSCRYPT_DIR" ]; then
        print_log "no conscrypt apex dir, skip apex store"
        return 0
    fi

    print_log "install apex store via $TEMP_DIR"
    mkdir -p "$TEMP_DIR" 2>/dev/null
    if [ -z "$(mount_root_at "$TEMP_DIR")" ]; then
        mount -t tmpfs tmpfs "$TEMP_DIR" 2>/dev/null
        print_log "mount tmpfs $TEMP_DIR status:$?"
    fi
    store_sync_to "$TEMP_DIR" apex
    set_selinux_context "$APEX_CONSCRYPT_DIR" "$TEMP_DIR"

    local tgt
    for tgt in $(apex_install_targets); do
        clear_our_mount "$tgt"
        mount -o bind "$TEMP_DIR" "$tgt" 2>/dev/null
        print_log "mount bind $TEMP_DIR $tgt status:$?"
    done

    # post-fs-data 阶段 zygote 通常还没起来；已经起来的就顺带注入
    local pid
    for pid in $(list_zygote_pids 2>/dev/null); do
        for tgt in $(apex_install_targets); do
            nsenter --mount="/proc/$pid/ns/mnt" -- /system/bin/mount -o bind "$TEMP_DIR" "$tgt" 2>/dev/null
            print_log "nsenter $pid bind $tgt status:$?"
        done
    done
    return 0
}

# ==================== 两种模式的入口 ====================

install_compatible_mode() {
    print_log "install mode: compatible (sdk=$sdk_version_number)"
    if [ "$sdk_version_number" -le 33 ]; then
        # Android 13 及以下：系统证书只在 /system，模块 overlay + bind 兜底
        install_legacy_store 1
    else
        # Android 14+：/system 与 APEX 两条路径都要有
        install_legacy_store 1
        install_apex_store
    fi
}

install_builtin_mode() {
    print_log "install mode: builtin (sdk=$sdk_version_number)"
    # 内置方式完全依赖 magisk magic mount / kernelsu overlayfs：
    # 只往模块目录写，不做 bind，不做兜底挂载
    install_legacy_store 0

    if [ "$sdk_version_number" -ge 34 ]; then
        print_log "install apex overlay dirs (builtin)"
        store_sync_to "$MODULE_APEX_CONSCRYPT_DIR" apex
        set_selinux_context "$APEX_CONSCRYPT_DIR" "$MODULE_APEX_CONSCRYPT_DIR"
        store_sync_to "$MODULE_APEX_CONSCRYPT_NUM_DIR" apex
        set_selinux_context "$APEX_CONSCRYPT_DIR" "$MODULE_APEX_CONSCRYPT_NUM_DIR"
        print_log "WARN: builtin mode relies on the module manager mounting $MODDIR/apex."
        print_log "      Magisk/KernelSU 只挂载 system/vendor/product 等分区，/apex 常常挂不上。"
        print_log "      Android 14+ 如果 Java 应用也抓不到包，请改用 compatible 模式（默认）。"
    fi
    return 0
}