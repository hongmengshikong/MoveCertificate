#!/system/bin/sh
# shellcheck shell=sh
# ============================================================================
# 启动时的状态记录 / 清理
# ============================================================================

MODDIR=${MODDIR:-${0%/*}}

# 清理 builtin 模式遗留的挂载目录文件
# 说明：compatible 模式下我们**需要** $MODULE_SYSTEM_CERT_DIR 生效
#       （这是 Flutter 读取的老路径），所以不能像以前那样把它清空。
clean_builtin_leftovers() {
    if [ "$CURRENT_MODE" != "builtin" ]; then
        # 只清理 apex 挂载目录，避免 builtin 模式残留的旧版本目录抢先挂载
        rm -f "$MODULE_APEX_CONSCRYPT_DIR"/* 2>/dev/null
        rm -f "$MODULE_APEX_CONSCRYPT_NUM_DIR"/* 2>/dev/null
        print_log "cleaned builtin apex leftovers"
    fi
}

# 记录系统原始证书列表（system 与 apex），去重后保存
# 用途：WebUI 区分"系统自带证书"和"用户证书"，以及运行时探针判断
record_system_certs() {
    print_log "Record original system certificates"
    # 如果 APEX 证书目录已经是模块挂载（action.sh / 手动执行脚本），
    # 这时录到的"系统证书"里会混进用户证书，直接跳过
    if [ -n "$(mount_root_at "$APEX_CONSCRYPT_DIR")" ]; then
        print_log "skip recording: $APEX_CONSCRYPT_DIR is already our mount"
        return 0
    fi
    if [ "$sdk_version_number" -le 33 ]; then
        ls -1 "$SYSTEM_CERT_DIR" >"$MODDIR/system_certs.txt" 2>/dev/null
    else
        if [ -d "$APEX_CONSCRYPT_DIR" ] && [ -n "$(ls -A "$APEX_CONSCRYPT_DIR" 2>/dev/null)" ]; then
            ls -1 "$APEX_CONSCRYPT_DIR" >"$MODDIR/system_certs.txt" 2>/dev/null
        else
            ls -1 "$SYSTEM_CERT_DIR" >"$MODDIR/system_certs.txt" 2>/dev/null
        fi
    fi
    sort -u "$MODDIR/system_certs.txt" -o "$MODDIR/system_certs.txt" 2>/dev/null
    print_log "recorded $(wc -l <"$MODDIR/system_certs.txt" 2>/dev/null) system certs"
}