#!/bin/sh
# ============================================================================
# 本地自测：在 /tmp 里伪造 Android 目录结构，验证证书仓库逻辑
# 用法：sh tools/selftest.sh
# ============================================================================
set -u
ROOT=${ROOT:-/tmp/mc-selftest}
MODSRC=$(cd "$(dirname "$0")/.." && pwd)

rm -rf "$ROOT"
mkdir -p "$ROOT/mod" "$ROOT/system" "$ROOT/apex" "$ROOT/temp" \
         "$ROOT/user0/cacerts-added" "$ROOT/user999/cacerts-added" \
         "$ROOT/custom" "$ROOT/stubs"

# ---------- 证书素材 ----------
gen_cert() {
    # $1 out-pem  $2 CN
    openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null \
        -out "$1" -days 30 -subj "/CN=$2/O=SelfTest" 2>/dev/null
}
i=1
while [ $i -le 25 ]; do
    gen_cert "$ROOT/system/system-ca-$i.pem" "System CA $i"
    i=$((i + 1))
done
i=1
while [ $i -le 25 ]; do
    gen_cert "$ROOT/apex/apex-ca-$i.pem" "Apex CA $i"
    i=$((i + 1))
done
# 用户证书（Android 用户库是 DER + hash 文件名）
gen_cert "$ROOT/user0/cacerts-added/user-ca.pem" "My Proxy CA"
H1=$(openssl x509 -in "$ROOT/user0/cacerts-added/user-ca.pem" -noout -subject_hash_old)
openssl x509 -in "$ROOT/user0/cacerts-added/user-ca.pem" -outform der -out "$ROOT/user0/cacerts-added/$H1.0"
cp "$ROOT/user0/cacerts-added/$H1.0" "$ROOT/user999/cacerts-added/$H1.1"
rm -f "$ROOT/user0/cacerts-added/user-ca.pem"

# 文件名 -> hash 目录格式（系统/APEX 目录里都是 PEM + hash 名）
for d in system apex; do
    for f in "$ROOT/$d"/*.pem; do
        [ -f "$f" ] || continue
        h=$(openssl x509 -in "$f" -noout -subject_hash_old)
        mv "$f" "$ROOT/$d/$h.0"
    done
done

# 自定义证书：一张 DER + 错误文件名（应被转 PEM，并尝试重命名/告警）
gen_cert "$ROOT/custom/weird.pem" "Custom Weird CA"
openssl x509 -in "$ROOT/custom/weird.pem" -outform der -out "$ROOT/custom/my-own-ca.der"
rm -f "$ROOT/custom/weird.pem"
# 一张 PEM + hash 名（应直接导入）
gen_cert "$ROOT/custom/good.pem" "Custom Good CA"
HG=$(openssl x509 -in "$ROOT/custom/good.pem" -noout -subject_hash_old)
mv "$ROOT/custom/good.pem" "$ROOT/custom/$HG.0"
# 一个垃圾文件（应被删除）
echo "not a cert" > "$ROOT/custom/junk.txt"

# ---------- 桩 ----------
cat >"$ROOT/stubs/getprop" <<'EOF'
#!/bin/sh
case "$1" in
    ro.build.version.sdk) echo 36 ;;
    sys.boot_completed) echo 1 ;;
    *) echo "" ;;
esac
EOF
cat >"$ROOT/stubs/getenforce" <<'EOF'
#!/bin/sh
echo Enforcing
EOF
cat >"$ROOT/stubs/chcon" <<'EOF'
#!/bin/sh
echo "chcon $*" >> "$MC_LOG_EXTRA"
EOF
cat >"$ROOT/stubs/chown" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$ROOT/stubs/pidof" <<'EOF'
#!/bin/sh
exit 1
EOF
cat >"$ROOT/stubs/nsenter" <<'EOF'
#!/bin/sh
echo "nsenter $*" >> "$MC_LOG_EXTRA"
exit 0
EOF
cat >"$ROOT/stubs/mount" <<'EOF'
#!/bin/sh
echo "mount $*" >> "$MC_LOG_EXTRA"
exit 0
EOF
cat >"$ROOT/stubs/umount" <<'EOF'
#!/bin/sh
echo "umount $*" >> "$MC_LOG_EXTRA"
exit 0
EOF
chmod +x "$ROOT/stubs/"*
export MC_LOG_EXTRA="$ROOT/extra.log"

# ---------- 复制模块 ----------
cp -r "$MODSRC/sh" "$ROOT/mod/"
cp "$MODSRC/post-fs-data.sh" "$MODSRC/service.sh" "$MODSRC/action.sh" "$ROOT/mod/"
mkdir -p "$ROOT/mod/certificates" "$ROOT/mod/system/etc/security/cacerts"
echo "mode=compatible" > "$ROOT/mod/mode.conf"

# ---------- 运行 ----------
PATH="$ROOT/stubs:$PATH"
export PATH
SYSTEM_CERT_DIR="$ROOT/system"
APEX_CONSCRYPT_DIR="$ROOT/apex"
USER_CERT_ROOT="$ROOT"
USER_CERT_DIR="$ROOT/user0/cacerts-added"
CUSTOM_CERT_DIR="$ROOT/custom"
TEMP_DIR="$ROOT/temp"
MODDIR="$ROOT/mod"
export SYSTEM_CERT_DIR APEX_CONSCRYPT_DIR USER_CERT_ROOT USER_CERT_DIR CUSTOM_CERT_DIR TEMP_DIR MODDIR

echo "---- post-fs-data ----"
sh "$ROOT/mod/post-fs-data.sh"
echo "exit=$?"

echo "---- install.log ----"
cat "$ROOT/mod/install.log"

FAIL=0
check() {
    if eval "$2"; then
        echo "PASS  $1"
    else
        echo "FAIL  $1"
        FAIL=1
    fi
}

STORE="$ROOT/mod/certificates"
OVERLAY="$ROOT/mod/system/etc/security/cacerts"

# 1. 仓库里的证书全部是 PEM
nonpem=$(for f in "$STORE"/*; do head -c 11 "$f" | grep -q -- "-----BEGIN" || echo "$f"; done)
check "store 全部为 PEM" '[ -z "$nonpem" ]'

# 2. 用户证书(DER)进了仓库且被转成 PEM，文件名保持 hash 名
check "用户证书已入库" '[ -f "$STORE/$H1.0" ]'
check "用户证书已转 PEM" 'head -c 11 "$STORE/$H1.0" | grep -q -- "-----BEGIN"'

# 3. 自定义 DER 证书被转成 PEM（有 openssl 时会顺手改成 hash 名）
RENAMED=$(ls "$ROOT/custom" | grep -E '^[0-9a-f]{8}\.0$' | head -n1)
check "自定义 DER 已转 PEM/改名 (新名字: $RENAMED)" '[ -n "$RENAMED" ] && head -c 11 "$ROOT/custom/$RENAMED" | grep -q -- "-----BEGIN"'

# 4. 垃圾文件不会被导入仓库（但不动用户的文件）
check "垃圾文件未入库" '[ ! -f "$STORE/junk.txt" ] && [ -f "$ROOT/custom/junk.txt" ]'

# 5. overlay 目录已同步 + 权限
check "overlay 已同步用户证书" '[ -f "$OVERLAY/$H1.0" ]'
check "overlay 证书权限 644" '[ "$(stat -c %a "$OVERLAY/$H1.0")" = "644" ]'

# 6. 数量检查
n=$(ls -1A "$STORE" | wc -l)
check "仓库证书数 >= 28 (实际 $n)" '[ "$n" -ge 28 ]'

# 6.1 幂等：再跑一次 post-fs-data，数量不能变
sh "$ROOT/mod/post-fs-data.sh" >/dev/null 2>&1
n2=$(ls -1A "$STORE" | wc -l)
check "重复执行幂等 ($n -> $n2)" '[ "$n" = "$n2" ]'

# 7. 没有残留临时文件
check "无 .tmp 残留" '[ -z "$(ls -1A "$STORE"| grep -E "tmp$")" ]'

# 8. bind 兜底被调用（因为 fake /system 里没有用户证书）
check "legacy 兜底 bind 被调用" 'grep -q "mount -o bind $ROOT/mod/system/etc/security/cacerts $ROOT/system" "$MC_LOG_EXTRA"'

echo "---- action ----"
sh "$ROOT/mod/action.sh" >"$ROOT/action.out" 2>&1
echo "exit=$?"
cat "$ROOT/action.out"
check "action 输出探针" 'grep -q "probe cert" "$ROOT/action.out"'


# ---------- builtin 模式 ----------
echo "---- builtin mode ----"
echo "mode=builtin" > "$ROOT/mod/mode.conf"
rm -rf "$ROOT/mod/certificates" "$ROOT/mod/system/etc/security/cacerts"
mkdir -p "$ROOT/mod/certificates"
sh "$ROOT/mod/post-fs-data.sh" >/dev/null 2>&1
check "builtin: 系统证书目录仍有 >=25 个证书" '[ "$(ls -1A "$ROOT/mod/system/etc/security/cacerts" | wc -l)" -ge 25 ]'
check "builtin: 用户证书已发布" '[ -f "$ROOT/mod/system/etc/security/cacerts/$H1.0" ]'
echo "mode=compatible" > "$ROOT/mod/mode.conf"

# ---------- 仓库过小保护 ----------
echo "---- store too small guard ----"
mkdir -p "$ROOT/empty-system" "$ROOT/empty-apex"
SYSTEM_CERT_DIR="$ROOT/empty-system" APEX_CONSCRYPT_DIR="$ROOT/empty-apex" \
    MODULE_CERT_DIR="$ROOT/mod/empty-store" \
    sh -c '. "$1/sh/common.sh"; . "$1/sh/store.sh"; prepare_cert_store; echo "rc=$?"' _ "$ROOT/mod" >"$ROOT/guard.out" 2>&1
check "空仓库被拒绝(rc!=0)" 'grep -q "rc=1" "$ROOT/guard.out"'

echo
if [ "$FAIL" = "0" ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit "$FAIL"