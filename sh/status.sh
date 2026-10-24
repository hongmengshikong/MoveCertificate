#!/system/bin/sh
# shellcheck shell=sh
# ============================================================================
# 状态报告
#   - 被 post-fs-data.sh / action.sh source 时：提供 status_report / write_status
#   - 直接执行时：
#       sh status.sh            → 人类可读状态
#       sh status.sh --json     → 单行 JSON（WebUI 用）
# ============================================================================

MODDIR=${MODDIR:-${0%/*}}

_probe_state() {
    # $1 目录  -> yes/no/empty/missing
    if [ ! -d "$1" ]; then
        echo "missing"
        return
    fi
    if [ -z "$(ls -A "$1" 2>/dev/null)" ]; then
        echo "empty"
        return
    fi
    if [ -n "$STORE_PROBE" ] && [ -f "$1/$STORE_PROBE" ]; then
        echo "yes"
    elif [ -n "$STORE_PROBE" ]; then
        echo "no"
    else
        echo "$(ls -1A "$1" 2>/dev/null | wc -l | tr -d ' ')"
    fi
}

_content_count() {
    [ -d "$1" ] || {
        echo 0
        return
    }
    ls -1A "$1" 2>/dev/null | wc -l | tr -d ' '
}

# ==================== 人类可读报告 ====================

status_report() {
    # pick_store_probe / pick_inject_src 会设置全局变量
    pick_store_probe 2>/dev/null
    pick_inject_src 2>/dev/null

    echo "=== MoveCertificate 状态 ==="
    echo "sdk           : $sdk_version_number"
    echo "mode          : $CURRENT_MODE"
    echo "cert store    : $(store_count) ($MODULE_CERT_DIR)"
    if [ -n "$STORE_PROBE" ]; then
        echo "probe cert    : $STORE_PROBE  (用户/自定义证书，用作探针)"
    else
        echo "probe cert    : <none>  (没有用户证书)"
    fi
    echo "/system/etc/security/cacerts : $(_content_count "$SYSTEM_CERT_DIR") 个文件, 探针: $(_probe_state "$SYSTEM_CERT_DIR")"
    if [ -d "$APEX_CONSCRYPT_DIR" ]; then
        echo "/apex/com.android.conscrypt/cacerts : $(_content_count "$APEX_CONSCRYPT_DIR") 个文件, 探针: $(_probe_state "$APEX_CONSCRYPT_DIR")"
    else
        echo "/apex/com.android.conscrypt/cacerts : 不存在（Android 13 及以下正常）"
    fi
    echo "注入源        : ${INJECT_SRC:-<未选择>}"

    local z
    for z in $(list_zygote_pids 2>/dev/null); do
        echo "zygote/usap   : pid $z (APEX 已注入: $(if ns_has_mount "$z" "${APEX_CONSCRYPT_DIR}"; then echo yes; else echo unknown; fi))"
    done

    if [ -n "$INJECT_SRC" ]; then
        local tgt
        for tgt in $(apex_install_targets 2>/dev/null); do
            if [ -n "$STORE_PROBE" ] && [ -f "$tgt/$STORE_PROBE" ]; then
                echo "挂载检查      : $tgt -> 有 $STORE_PROBE"
            else
                echo "挂载检查      : $tgt -> 没有 $STORE_PROBE"
            fi
        done
    fi

    echo
    echo "提示："
    echo "  1. 证书放 /data/local/tmp/cert 后需要【重启】或点模块的【Action】按钮重新应用"
    echo "  2. 文件名必须是 <subject_hash_old>.0，内容建议 PEM（模块会自动把 DER 转 PEM）"
    echo "  3. KernelSU 请确认该 app 的 App Profile 没有开启【卸载模块】"
    echo "  4. Flutter 应用修改证书后需要【强杀 app 再打开】"
}

# ==================== JSON（WebUI 用） ====================

status_json() {
    pick_store_probe 2>/dev/null

    local probe store system_n apex_n ps=0 pa=0 inj=0 zy=0 z t targets ver
    probe="$STORE_PROBE"
    store=$(store_count)
    system_n=$(_content_count "$SYSTEM_CERT_DIR")
    apex_n=$(_content_count "$APEX_CONSCRYPT_DIR")
    if [ -n "$probe" ]; then
        [ -f "$SYSTEM_CERT_DIR/$probe" ] && ps=1
        [ -f "$APEX_CONSCRYPT_DIR/$probe" ] && pa=1
    fi

    targets=$(apex_install_targets 2>/dev/null)
    for z in $(list_zygote_pids 2>/dev/null); do
        zy=$((zy + 1))
        for t in $targets; do
            if ns_has_mount "$z" "$t" 2>/dev/null; then
                inj=$((inj + 1))
                break
            fi
        done
    done

    ver=$(grep -m1 '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2-)
    [ -n "$ver" ] || ver="unknown"

    printf '{"ok":true,"sdk":%s,"mode":"%s","store":%s,"system":%s,"apex":%s,"probe":"%s","probeSystem":%s,"probeApex":%s,"injected":%s,"zygotes":%s,"version":"%s"}\n' \
        "${sdk_version_number:-0}" "$CURRENT_MODE" "$store" "$system_n" "$apex_n" \
        "$probe" "$ps" "$pa" "$inj" "$zy" "$ver"
}

write_status() {
    status_report >"$MODDIR/status.txt" 2>/dev/null
    print_log "status written to $MODDIR/status.txt"
}

# ==================== 直接执行入口 ====================

case "${0##*/}" in
    status.sh)
        MODDIR=$(cd "${0%/*}/.." 2>/dev/null && pwd)
        . "$MODDIR/sh/common.sh"
        . "$MODDIR/sh/store.sh"
        . "$MODDIR/sh/inject.sh"
        read_mode_config
        case "$1" in
            --json) status_json ;;
            *) status_report ;;
        esac
        exit 0
        ;;
esac
