#!/system/bin/sh
# ============================================================================
# MoveCertificate - service.sh
# ----------------------------------------------------------------------------
# late_start 阶段执行：启动注入守护进程。
# /apex 是 MS_PRIVATE 传播，post-fs-data 阶段做的 bind 不一定能出现在
# 已经启动的 app 进程的 mount namespace 里，所以需要常驻注入。
# ============================================================================

MODDIR=${0%/*}

. "$MODDIR/sh/common.sh"
. "$MODDIR/sh/store.sh"
. "$MODDIR/sh/inject.sh"

print_log "=== MoveCertificate service.sh ==="
start_injection_supervisor
