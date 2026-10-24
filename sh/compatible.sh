#!/system/bin/sh
# shellcheck shell=sh
# ============================================================================
# 兼容模式（tmpfs + bind 挂载）
# ----------------------------------------------------------------------------
# 具体实现已统一到 sh/store.sh 的 install_compatible_mode()，
# 这里只保留旧的函数名，避免旧脚本 / 旧调用方式失效。
# ============================================================================

MODDIR=${MODDIR:-${0%/*}}

# Android 13 及以下
init_low_version() {
    install_compatible_mode
}

# Android 14 及以上
init_high_version() {
    install_compatible_mode
}

# 旧函数：把证书目录 bind 到 /system/etc/security/cacerts
# 现在默认走模块 overlay（magic mount），只有 overlay 没生效时才 bind
mount_legacy_cacerts_dir() {
    install_legacy_store 1
}
