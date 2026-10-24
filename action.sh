#!/system/bin/sh
# ============================================================================
# MoveCertificate - action.sh
# ----------------------------------------------------------------------------
# KernelSU / APatch 的「Action」按钮：不重启，立刻重新应用证书。
#   - 重新导入 /data/local/tmp/cert 与用户证书
#   - 重新发布 /system 与 /apex 证书目录
#   - 给已经在跑的 app / zygote 注入挂载
# 注意：已经建立好 TLS 连接的 app 需要强杀重开。
# ============================================================================

MODDIR=${0%/*}

. "$MODDIR/sh/common.sh"
. "$MODDIR/sh/store.sh"
. "$MODDIR/sh/inject.sh"
. "$MODDIR/sh/compatible.sh"
. "$MODDIR/sh/built-in.sh"
. "$MODDIR/sh/refresh.sh"
. "$MODDIR/sh/status.sh"

print_log "=== MoveCertificate action.sh ==="

read_mode_config
# 只在没有记录过系统证书列表时记录（开机时已经记过，
# 重复记录会把模块自己发布进去的用户证书当成"系统证书"）
[ -f "$MODDIR/system_certs.txt" ] || record_system_certs

if prepare_cert_store; then
    if [ "$CURRENT_MODE" = "builtin" ]; then
        install_builtin_mode
    else
        install_compatible_mode
    fi
    inject_once
    print_log "certificates re-applied"
else
    print_log "ERROR: cert store not ready"
fi

write_status
status_report
