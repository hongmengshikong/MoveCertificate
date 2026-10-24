#!/system/bin/sh
# ============================================================================
# MoveCertificate - post-fs-data
# ----------------------------------------------------------------------------
# 开机早期执行，负责：
#   1. 组装合并证书仓库（系统证书 + 用户证书 + 自定义证书，统一 PEM）
#   2. 发布到 /system/etc/security/cacerts （模块 overlay，Flutter 老路径）
#   3. 发布到 /apex/com.android.conscrypt/cacerts （tmpfs + bind，Java 路径）
# ============================================================================

MODDIR=${0%/*}

. "$MODDIR/sh/common.sh"
. "$MODDIR/sh/store.sh"
. "$MODDIR/sh/inject.sh"
. "$MODDIR/sh/compatible.sh"
. "$MODDIR/sh/built-in.sh"
. "$MODDIR/sh/refresh.sh"
. "$MODDIR/sh/status.sh"

log_reset
print_log "=== MoveCertificate post-fs-data start ==="
print_log "sdk=$sdk_version_number"

read_mode_config
print_log "mode=$CURRENT_MODE"

clean_builtin_leftovers
record_system_certs

if prepare_cert_store; then
    if [ "$CURRENT_MODE" = "builtin" ]; then
        install_builtin_mode
    else
        install_compatible_mode
    fi
    print_log "certificates installed"
else
    print_log "ERROR: cert store not ready, skip install (system CA keeps untouched)"
fi

write_status
print_log "=== MoveCertificate post-fs-data end ==="
