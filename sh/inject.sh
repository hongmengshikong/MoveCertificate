#!/system/bin/sh
# shellcheck shell=sh
# ============================================================================
# MoveCertificate - 运行时挂载注入
# ----------------------------------------------------------------------------
# 为什么需要它：
#   Android 14+ 的 /apex 是 init 用 MS_PRIVATE 挂载的（传播属性 private），
#   在 init 的 mount namespace 里往 /apex/... 上 bind 的内容，
#   不一定会出现在已经启动的 app 进程的 mount namespace 里。
#   app 是 zygote fork 出来的，各自带一份从 zygote 复制来的 namespace，
#   所以必须：
#     1. 往 zygote / usap 的 namespace 里 bind（之后新启动的 app 自动继承）
#     2. 往已经在跑的 app 进程的 namespace 里 bind（zygote 重启后也要重来）
#   这也正是 Flutter/Java 在 A16 上「证书看着装好了，却抓不到包」的原因之一。
# ============================================================================

NSENTER_BIN=$(command -v nsenter 2>/dev/null)
[ -n "$NSENTER_BIN" ] || NSENTER_BIN=/system/bin/nsenter
MOUNT_BIN=$(command -v mount 2>/dev/null)
[ -n "$MOUNT_BIN" ] || MOUNT_BIN=/system/bin/mount

INJECT_SRC=""
STORE_PROBE=""
APEX_TARGETS=""

# 目标进程：zygote / zygote64 / usap32 / usap64 / webview_zygote
list_zygote_pids() {
    pidof zygote zygote64 usap32 usap64 webview_zygote 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u
}

# $1 的父进程 pid
ppid_of() {
    awk '{ sub(/^[^)]*\) /, ""); print $2 }' "/proc/$1/stat" 2>/dev/null
}

# 该进程的 namespace 里，$2 这个挂载点是否已经有挂载
ns_has_mount() {
    local pid="$1" tgt="$2"
    [ -r "/proc/$pid/mountinfo" ] || return 1
    awk -v t="$tgt" '$5 == t { found = 1 } END { exit(found ? 0 : 1) }' "/proc/$pid/mountinfo" 2>/dev/null
}

# 该进程能不能在 $2 目录里看到我们的探针证书
ns_has_store() {
    local pid="$1" tgt="$2"
    [ -n "$STORE_PROBE" ] || return 1
    [ -e "/proc/$pid/root$tgt/$STORE_PROBE" ]
}

# 选择注入源
#   优先模块 overlay 目录：在 /data 上，任何 namespace 都可见，内容一定是最新的
#   其次 tmpfs 暂存目录：SELinux 上下文和 APEX 目录完全一致
#   最后合并仓库
pick_inject_src() {
    if [ -d "$MODULE_SYSTEM_CERT_DIR" ] && [ -n "$(ls -A "$MODULE_SYSTEM_CERT_DIR" 2>/dev/null)" ]; then
        INJECT_SRC="$MODULE_SYSTEM_CERT_DIR"
    elif [ -d "$TEMP_DIR" ] && [ -n "$(ls -A "$TEMP_DIR" 2>/dev/null)" ]; then
        INJECT_SRC="$TEMP_DIR"
    elif [ -d "$MODULE_CERT_DIR" ] && [ -n "$(ls -A "$MODULE_CERT_DIR" 2>/dev/null)" ]; then
        INJECT_SRC="$MODULE_CERT_DIR"
    else
        INJECT_SRC=""
    fi
    [ -n "$INJECT_SRC" ]
}

# 给单个进程注入
inject_pid() {
    local pid="$1" tgt changed=0
    [ -d "/proc/$pid" ] || return 1
    [ -n "$INJECT_SRC" ] || return 1

    for tgt in $APEX_TARGETS; do
        # 这个 namespace 里没有该路径（APEX 没挂进来），跳过
        [ -e "/proc/$pid/root$tgt" ] || continue

        if ns_has_mount "$pid" "$tgt"; then
            continue
        fi
        if ns_has_store "$pid" "$tgt"; then
            continue
        fi

        if $NSENTER_BIN --mount="/proc/$pid/ns/mnt" -- $MOUNT_BIN -o bind "$INJECT_SRC" "$tgt" 2>/dev/null; then
            changed=1
        else
            print_log "inject FAILED pid=$pid src=$INJECT_SRC tgt=$tgt"
        fi
    done

    if [ "$changed" = "1" ]; then
        print_log "inject OK pid=$pid src=$INJECT_SRC"
    fi
    return 0
}

# 全量扫描：zygote 自己 + 它们的子进程（app / isolated / usap）
inject_all_apps() {
    local zygotes padded pid ppid
    zygotes=$(list_zygote_pids)
    padded=" $(echo "$zygotes" | tr '\n' ' ') "

    for pid in $zygotes; do
        inject_pid "$pid"
    done

    for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
        [ -d "/proc/$pid" ] || continue
        [ "$pid" = "$$" ] && continue
        ppid=$(ppid_of "$pid")
        [ -n "$ppid" ] || continue
        case "$padded" in
            *" $ppid "*) inject_pid "$pid" ;;
        esac
    done
    return 0
}

# 一次性的注入（action.sh 用）
inject_once() {
    pick_inject_src || {
        print_log "inject: no cert store to inject"
        return 1
    }
    APEX_TARGETS=$(apex_install_targets)
    if [ -z "$APEX_TARGETS" ]; then
        print_log "inject: no conscrypt apex target"
        return 1
    fi
    pick_store_probe
    inject_all_apps
    return 0
}

# 常驻守护：保证 zygote 重启 / 新 app 启动后依然生效
inject_supervisor_run() {
    local n=0 now last_full=0 z

    while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
        n=$((n + 1))
        [ "$n" -gt 180 ] && break
        sleep 1
    done
    sleep 3

    pick_inject_src || {
        print_log "inject supervisor: no cert store, exit"
        return 1
    }
    APEX_TARGETS=$(apex_install_targets)
    if [ -z "$APEX_TARGETS" ]; then
        print_log "inject supervisor: no conscrypt apex, exit"
        return 1
    fi
    pick_store_probe
    print_log "inject supervisor: src=$INJECT_SRC probe=$STORE_PROBE targets=$(echo $APEX_TARGETS)"

    last_full=0
    while true; do
        for z in $(list_zygote_pids); do
            inject_pid "$z"
        done

        now=$(date +%s 2>/dev/null)
        [ -n "$now" ] || now=0
        if [ $((now - last_full)) -ge 30 ] || [ "$last_full" = "0" ]; then
            inject_all_apps
            last_full=$now
        fi
        sleep 5
    done
}

start_injection_supervisor() {
    inject_supervisor_run >/dev/null 2>&1 &
    print_log "injection supervisor started (pid $!)"
    return 0
}