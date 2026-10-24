#!/system/bin/sh
# shellcheck shell=sh
# ============================================================================
# MoveCertificate - 公共定义 / 工具函数
# 由 post-fs-data.sh / service.sh / action.sh 通过 "." 引入
# ============================================================================

MODDIR=${MODDIR:-${0%/*}}
# 兼容 `cd 到模块目录后 sh post-fs-data.sh` 这种调用方式（此时 $0 没有斜杠）
if [ ! -d "$MODDIR/sh" ]; then
    MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
fi
# 统一成绝对路径（日志 / status.txt 里更好读）
case "$MODDIR" in
    /*) ;;
    *) MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd) ;;
esac

# ==================== 日志 ====================
LOG_PATH=${LOG_PATH:-$MODDIR/install.log}
LOG_TAG="iyue"

# 清空日志（只在 post-fs-data / action 开头调用一次，
# 避免 service.sh 再次清空把开机日志冲掉）
log_reset() {
    : >"$LOG_PATH"
}

print_log() {
    echo "[$LOG_TAG] $*" >>"$LOG_PATH" 2>/dev/null
}

# ==================== Android 版本 ====================
if [ -z "${sdk_version}" ]; then
    sdk_version=$(getprop ro.build.version.sdk 2>/dev/null)
fi
[ -n "${sdk_version}" ] || sdk_version=0
sdk_version_number=$(expr "$sdk_version" + 0 2>/dev/null)
[ -n "${sdk_version_number}" ] || sdk_version_number=0

# ==================== 路径定义 ====================
# 全部用 ${VAR:=默认值} 形式，便于本地测试时覆盖，不影响真机默认行为

## 系统证书目录（Android 13 及以下放这里，14+ 仍保留一份）
: "${SYSTEM_CERT_DIR:=/system/etc/security/cacerts}"
## Android 14+ conscrypt APEX 证书目录（真正的系统证书库）
: "${APEX_CONSCRYPT_DIR:=/apex/com.android.conscrypt/cacerts}"
## 用户证书（设置里安装的，默认用户）
: "${USER_CERT_ROOT:=/data/misc/user}"
: "${USER_CERT_DIR:=$USER_CERT_ROOT/0/cacerts-added}"
## 自定义证书目录（手动 push 的证书）
: "${CUSTOM_CERT_DIR:=/data/local/tmp/cert}"
## 兼容模式的 tmpfs 暂存目录（内容会被 bind 到 APEX）
: "${TEMP_DIR:=/mnt/instaler}"

## 模块目录
## 合并后的证书仓库：系统证书 + 用户证书 + 自定义证书，统一转 PEM
: "${MODULE_CERT_DIR:=$MODDIR/certificates}"
## 模块内置挂载点：/system/etc/security/cacerts（magic mount / overlayfs）
: "${MODULE_SYSTEM_CERT_DIR:=$MODDIR/system/etc/security/cacerts}"
## 模块内置挂载点：/apex/com.android.conscrypt/cacerts
: "${MODULE_APEX_CONSCRYPT_DIR:=$MODDIR/apex/com.android.conscrypt/cacerts}"

## 带版本号的 conscrypt 目录名，例如 com.android.conscrypt@361411000
APEX_CONSCRYPT_NUM_NAME=${APEX_CONSCRYPT_NUM_NAME:-$(basename "$(find /apex -type d -name 'com.android.conscrypt@*' 2>/dev/null | head -n1)")}
: "${MODULE_APEX_CONSCRYPT_NUM_DIR:=$MODDIR/apex/$APEX_CONSCRYPT_NUM_NAME/cacerts}"

## 证书文件的 SELinux 类型（AOSP: /system/etc/security/cacerts(/.*)? 就是这个类型）
SELINUX_CACERTS_DEFAULT=u:object_r:system_security_cacerts_file:s0

# ==================== 模式配置 ====================
# 配置文件：$MODDIR/mode.conf
# 内容：mode=compatible 或 mode=builtin
CONFIG_FILE=${CONFIG_FILE:-$MODDIR/mode.conf}
CURRENT_MODE="compatible"

read_mode_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_log "Config file $CONFIG_FILE not found, using default mode: compatible"
        CURRENT_MODE="compatible"
        return 0
    fi

    local raw
    raw=$(grep -m1 '^[[:space:]]*mode=' "$CONFIG_FILE" 2>/dev/null)

    if [ -z "$raw" ]; then
        print_log "Config file $CONFIG_FILE has no valid 'mode=' entry, using default: compatible"
        CURRENT_MODE="compatible"
        return 0
    fi

    local mode_val
    mode_val=$(echo "$raw" | sed 's/^[[:space:]]*mode[[:space:]]*=[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')

    case "$mode_val" in
        compatible|builtin)
            CURRENT_MODE="$mode_val"
            print_log "Read mode config: $CURRENT_MODE"
            ;;
        *)
            print_log "Unknown mode '$mode_val' in $CONFIG_FILE, falling back to default: compatible"
            CURRENT_MODE="compatible"
            ;;
    esac
}

# ==================== 权限 / SELinux ====================
fix_user_permissions() {
    [ -d "$USER_CERT_DIR" ] || return 0
    chown -R root:root "$USER_CERT_DIR"/ 2>/dev/null
    chmod -R 666 "$USER_CERT_DIR"/* 2>/dev/null
    chown system:system "$USER_CERT_DIR" 2>/dev/null
    chmod 755 "$USER_CERT_DIR" 2>/dev/null
    print_log "fix user certificate permissions status:$?"
}

# 系统证书目录权限（Android 13 及以下 / 模块 overlay 用）
fix_system_permissions() {
    [ -d "$1" ] || return 0
    chown root:root "$1" 2>/dev/null
    chown -R root:root "$1" 2>/dev/null
    chmod -R 644 "$1"/* 2>/dev/null
    chmod 755 "$1" 2>/dev/null
    if command -v chcon >/dev/null 2>&1; then
        chcon u:object_r:system_file:s0 "$1"/* 2>/dev/null
    fi
    if [ -n "$(ls -A "$1" 2>/dev/null)" ]; then
        touch -t 200901010800 "$1"/* 2>/dev/null
    fi
    touch -t 200901010800 "$1" 2>/dev/null
    print_log "fix permissions $1 status:$?"
}

# Android 14+ APEX 证书目录权限
fix_system_permissions14() {
    [ -d "$1" ] || return 0
    chown -R system:system "$1"/* 2>/dev/null
    chown -R system:system "$1" 2>/dev/null
    chmod -R 644 "$1"/* 2>/dev/null
    chmod 755 "$1" 2>/dev/null
    # 空目录时 "$1"/* 不会展开，touch 会创建一个名为 "*" 的文件污染目录
    if [ -n "$(ls -A "$1" 2>/dev/null)" ]; then
        touch -t 197001010800 "$1"/* 2>/dev/null
    fi
    touch -t 197001010800 "$1" 2>/dev/null
    print_log "fix permissions14 $1 status:$?"
}

# 把 $2 的 SELinux 上下文刷成和 $1 一致（$1 不存在时用默认类型）
set_selinux_context() {
    local src="$1"
    local dst="$2"
    [ -n "$dst" ] && [ -d "$dst" ] || return 0
    command -v chcon >/dev/null 2>&1 || return 0
    [ "$(getenforce 2>/dev/null)" = "Enforcing" ] || return 0

    if [ -n "$src" ] && [ -e "$src" ]; then
        local ctx
        ctx=$(ls -Zd "$src" 2>/dev/null | awk '{print $1}')
        if [ -z "$ctx" ] || [ "$ctx" = "?" ]; then
            ctx=$SELINUX_CACERTS_DEFAULT
        fi
    else
        ctx=$SELINUX_CACERTS_DEFAULT
    fi

    chcon -R "$ctx" "$dst" 2>/dev/null
    print_log "set selinux context $dst -> $ctx status:$?"
}

# ==================== 兼容性清理 ====================
# 清理 AdGuard 证书冲突 + 模块内过期的 conscrypt 版本号目录
compatible() {
    print_log "Compatible adguard"
    cert_dir="$MODULE_CERT_DIR"
    print_log "Running compatibility cleanup for potentially conflicting certificates."

    rm -f "$cert_dir"/47ec1af8.* 2>/dev/null
    print_log "Removed files matching '47ec1af8.*'."

    for cert_file in "$cert_dir"/*; do
        [ -f "$cert_file" ] || continue
        if grep -q "Guard Personal Intermediate" "$cert_file" 2>/dev/null; then
            print_log "Removing file containing 'Guard Personal Intermediate': ${cert_file##*/}"
            rm -f "$cert_file"
        fi
    done
    print_log "Compatibility cleanup status:$?"

    # 支持 OTA 后大版本更新：删除与当前系统版本不一致的旧 conscrypt 目录，
    # 避免 find 顺序不确定导致取错目录
    for apex_dir in "$MODDIR"/apex/com.android.conscrypt@*; do
        [ -d "$apex_dir" ] || continue
        apex_num_name=$(basename "$apex_dir")
        if [ "$apex_num_name" != "$APEX_CONSCRYPT_NUM_NAME" ]; then
            rm -rf "$MODDIR/apex/$apex_num_name" 2>/dev/null
            print_log "Removed old conscrypt directory: $MODDIR/apex/$apex_num_name"
        fi
    done
    mkdir -p -m 755 "$MODULE_APEX_CONSCRYPT_NUM_DIR" 2>/dev/null
}

# 兼容旧函数名（其它脚本可能还在调用）
move_custom_cert() {
    if command -v store_import_custom >/dev/null 2>&1; then
        store_import_custom
    fi
}