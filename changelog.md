### v1.7.1-flutter16（文档修订 / 回退）

**明确范围：只修 Android 16 的 Flutter 抓包；撤回 v1.8.0 的 A14/15 修复**

* v1.8.0 尝试的「Android 14 / 15 抓不到包」修复在真机上**实测无效**，
  代码已整体回退到 v1.7.1（版本号 / versionCode 保持 v1.7.1 / 32）。
* 文档中删除了「A14/15/16 全版本可用」的说法：
  * Flutter 抓包修复**只针对 Android 16（SDK 36）**，并在 Android 16 真机上验证；
  * **Android 14 / 15 未修复、未验证**，请继续使用旧版 `MoveCertificate-v1.5.6.zip`。
* `tools/version-matrix.sh` 的结论仅代表"证书文件被写入"，不代表 app 命名空间里可见，文档已注明。
* 只改了文档与打包说明，模块运行逻辑与 v1.7.1 完全一致。

### v1.7.1-flutter16（fork）

**重做 WebUI（参考 AlwaysStrong 的视觉语言）+ 实时状态页**

* 新界面
  * 大标题 Hero + 状态胶囊、分组卡片、彩色图标块、底部四标签导航
  * 深色 / 浅色 / 跟随系统三态；语言改为底部弹层（中文 / English / Türkçe / 跟随系统）
  * 证书行：状态胶囊 + 一键删除（确认弹窗），不再需要长按
  * 模式切换：分段控件 + 确认弹窗（写入 mode.conf）
* 新增「模块状态」卡片
  * 运行模式、证书仓库数量
  * `/system/etc/security/cacerts` 与 `/apex/com.android.conscrypt/cacerts` 的探针结果
  * 注入进程数（zygote / usap / app 命名空间）
* `sh/status.sh` 支持直接执行
  * `sh status.sh` → 人类可读状态
  * `sh status.sh --json` → WebUI 使用的单行 JSON
* 版本：v1.7.1 / versionCode 32

### v1.7.0-flutter16（fork）

**修复：Android 16 上 Flutter / Dart 应用抓不到包（同时保留 A14/A15 的修复）**

* 根因 1：证书格式
  * Dart 的 `security_context_linux.cc` 用 `SSL_CTX_load_verify_locations(ctx, NULL, dir)`
    加载根证书，BoringSSL 的 `x509_d2.cc` 里是
    `X509_LOOKUP_add_dir(lookup, path, X509_FILETYPE_PEM)` —— **只解析 PEM**。
  * Android 在设置里安装的用户证书（`/data/misc/user/0/cacerts-added/<hash>.0`）是 **DER**
    （AOSP `TrustedCertificateStore.writeCertificate()` 写的是 `cert.getEncoded()`）。
  * 旧模块原样复制 DER → Java 能读、Flutter 读不到；而且旧 README 还让人把证书转成 DER，
    等于把 Flutter 彻底排除在外。
  * 修复：合并仓库统一转 **PEM**，文件名保持 `<subject_hash_old>.0`；
    `/data/local/tmp/cert` 同时接受 PEM 和 DER（DER 自动转换），文件名不对时用 openssl
    或「同内容证书的名字」自动纠正。

* 根因 2：老路径在 A16 上没生效
  * Flutter 老引擎只读 `/system/etc/security/cacerts`；compatible 模式只把它 bind 进
    init 的 namespace，A16 上实测 app 里看不到用户证书（证书只出现在 APEX 目录）。
  * 修复：改为写入**模块 overlay 目录** `$MODDIR/system/etc/security/cacerts`，
    由 magisk magic mount / kernelsu overlayfs 提供给所有进程；
    再用「用户证书是否可见」做探针，overlay 没生效时自动 bind 兜底。

* 根因 3：`/apex` 私有传播
  * Android 14+ 的 `/apex` 是 MS_PRIVATE 挂载，init namespace 里的 bind 不保证出现在
    已运行 app 的 namespace 里。
  * 修复：新增 `sh/inject.sh` + `service.sh` 常驻守护，
    周期性对 zygote / zygote64 / usap32 / usap64 以及它们的子进程执行
    `nsenter --mount=/proc/<pid>/ns/mnt -- mount -o bind <store> /apex/com.android.conscrypt/cacerts`，
    zygote 崩溃重启后会自动重新注入。

* 其它
  * 新增 `action.sh`：不重启即可重新应用证书，并打印状态报告。
  * 新增 `sh/status.sh`：证书数量、两条路径是否带探针、挂载情况。
  * 新增本地自测：`tools/selftest.sh`（目录/格式/幂等）与
    `tools/flutter-store-test.sh`（用真实 Dart VM 验证 PEM 才能被 Flutter 信任）。
  * `clean_builtin_leftovers` 不再清空 `$MODULE_SYSTEM_CERT_DIR`
    （compatible 模式现在需要它）。
  * builtin 模式不再先 `rm -rf` 再只放用户证书，数量 < 20 时直接放弃。

* 验证
  * Dart VM（与 libflutter.so 同一套 BoringSSL 代码）：
    `<hash>.0` + DER → `CERTIFICATE_VERIFY_FAILED`；`<hash>.0` + PEM → HTTP 200。
  * 本地模拟 A16 目录结构跑 post-fs-data / action 全部通过，重复执行幂等。
  * **真机 Android 16（SDK 36 / KernelSU）**：两条路径各 150 张 PEM，
    Flutter app 进程 namespace 内可见 `dce076e2.0`，抓包成功。

### v1.6.4-fix (fork)

**修复：built-in 模式会把系统 CA 全部清空（严重）**

* 现象
  * init_low_builtin_method / init_high_builtin_method 都是先 `rm -rf $MODULE_CERT_DIR/*`，
    然后**只把用户证书**拷进去，再整体覆盖到 `/system/etc/security/cacerts`（或 APEX 目录）。
  * 等于把系统 CA 目录替换成"只有你的抓包证书" —— 加载成功后所有公共 CA
    （Google / GitHub / 游戏服务端 …）全部失效，TLS 全面崩，比抓不到包更严重。
  * built-in 模式此前也没给 `/system/etc/security/cacerts` 补用户证书，
    Flutter/Dart 应用（读老路径）依旧抓不到。

* 修改
  * 先**备份系统证书**到 `$MODULE_CERT_DIR`（low: `/system/etc/security/cacerts`，
    high: `/apex/com.android.conscrypt/cacerts`），再叠加用户证书。
  * 加保护：拷贝完若证书数 < 20，直接 `return 1` 放弃，绝不拿残缺集合覆盖系统目录。
  * built-in 模式补上 `$MODULE_SYSTEM_CERT_DIR`（legacy 路径），Flutter/Dart 也能用。
  * 所有目标目录先 `mkdir -p`，避免首次安装目录不存在导致 `cp` 失败。
  * 日志打印实际证书数，便于排查。

* 验证
  * 在 Android 16 上以临时 MODDIR 跑 init_high_builtin_method：
    `built-in certs: 150` / `apex_dir=150` / `apex_num_dir=150` / `system_dir=150`。

### v1.6.3-fix (fork)

**修复：Flutter / Dart 应用在 MITM 下抓不到包**

* 现象
  * Android 14+ 上 `compatible` 模式只把证书 bind 到 `/apex/com.android.conscrypt/cacerts`，
    `/system/etc/security/cacerts` 保持原样（没有用户证书）。
  * 但 Flutter/Dart 的 BoringSSL（`libflutter.so` 里硬编码）读的是
    **`/system/etc/security/cacerts`** 这条老路径。
  * 结果：小黄鸟/HttpCanary/Charles 对 Flutter 应用抓包时 TLS 握手失败，
    看起来像"抓不到包"；而普通 Java 应用正常。
  * v1.5.6 是先把 tmpfs 挂到 `/system/etc/security/cacerts` 再 bind 给 APEX，
    所以老版本能用、新版本反而不能用。

* 修改
  * `sh/compatible.sh` 新增 `mount_legacy_cacerts_dir()`：
    在 `init_high_version()` 里把同一份 `$TEMP_DIR` 也 bind 到
    `/system/etc/security/cacerts`，并 `nsenter` 同步 pid 1 / zygote 的 mount namespace。
  * 若是软链且指向 APEX 目录，则跳过（已被覆盖）。
  * 重复执行时先 umount，保证幂等。

* 验证（Android 16 / Android 15 实机）
  * `ls /system/etc/security/cacerts | wc -l` = 原系统数 + 用户证书数
  * 用户证书 `<hash>.0` 在 **两个** 目录里都能看到
  * Flutter 应用进程内可直接读到该证书文件

* 版本
  * v1.6.3-fix / versionCode 29