#!/system/bin/sh
# shellcheck shell=sh
# ============================================================================
# 内置模式（magisk magic mount / kernelsu overlayfs）
# ----------------------------------------------------------------------------
# 具体实现已统一到 sh/store.sh 的 install_builtin_mode()，
# 这里只保留旧的函数名。
#
# 注意：旧实现会先 rm -rf $MODULE_CERT_DIR/* 再只放用户证书，
# 等于把系统 CA 目录替换成"只有用户证书"，导致整机 TLS 崩掉。
# 新实现先合并系统证书 + 用户证书，数量 < 20 时直接放弃。
# ============================================================================

MODDIR=${MODDIR:-${0%/*}}

init_low_builtin_method() {
    install_builtin_mode
}

init_high_builtin_method() {
    install_builtin_mode
}
