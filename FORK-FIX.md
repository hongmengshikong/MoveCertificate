# FORK: Flutter / Android 16 抓包修复（v1.7.0-flutter16）

## 一、结论（先看这个）

Flutter/Dart 的根证书加载和 Java 完全是两条路：

* Dart：`runtime/bin/security_context_linux.cc` →
  `SSL_CTX_load_verify_locations(ctx, NULL, <dir>)`
* BoringSSL：`crypto/x509/x509_d2.cc` →
  `X509_LOOKUP_add_dir(lookup, path, X509_FILETYPE_PEM)`
  → 只按 **PEM** 解析；`crypto/x509/by_dir.cc` 只按
  `<X509_NAME_hash>.0` / `<X509_NAME_hash_old>.0` 找文件。

所以 Flutter 要能 MITM，三个条件缺一不可：

1. 证书目录在 **app 进程的 mount namespace** 里可见；
2. 文件内容是 **PEM**；
3. 文件名是 **subject hash**（`openssl x509 -subject_hash_old`）。

而 Android 在设置里安装的用户证书是 **DER**（`TrustedCertificateStore.writeCertificate()`
里 `os.write(cert.getEncoded())`），旧版模块原样复制，于是 Java 能抓、Flutter 抓不到。

## 二、验证（真实 Dart VM，不是"我觉得"）

同一份 CA，做成不同目录，用 Dart VM 的 `--root-certs-cache`（就是
`LoadRootCertCache` 那个入口）去连由该 CA 签发的本地 HTTPS：

| 目录内容 | 结果 |
|---|---|
| `<hash_old>.0` + **DER**（Android 用户证书原样） | ❌ `CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate` |
| `<hash_old>.0` + **PEM** | ✅ `RESULT OK 200` |
| `<hash_new>.0` + PEM | ✅（BoringSSL 新旧 hash 都会试） |
| `myca.pem` + PEM（名字不是 hash） | ❌ 找不到 |

复现脚本：`tools/flutter-store-test.sh`（需要 openssl / python3 / Dart SDK）。

## 三、改了哪些东西

### 1. `sh/store.sh`（新增）：合并证书仓库

* 来源：APEX（A14+）/ `/system`（<=A13）的系统证书 + 所有用户的
  `cacerts-added` + `/data/local/tmp/cert`。
* `store_normalize()`：把 DER 全部转成 PEM（`base64` + 64 列换行，纯 shell 实现）。
* `store_import_custom()`：PEM/DER 都收；文件名不是 hash 时，优先用 `openssl`
  算 hash，其次找仓库里"内容相同、名字合法"的证书借用名字；都没有则告警
  （Java 可用、Flutter 不可用）。
* 保护：合并完证书数 < 20 直接放弃，绝不用残缺集合覆盖系统目录。

### 2. `/system/etc/security/cacerts`：改用模块 overlay

旧实现是 post-fs-data 里 `mount tmpfs` + `bind`。在 A16 上实测（
NVISO AlwaysTrustUserCerts#52 也是同样现象）：证书只出现在 APEX 目录，
`/system/etc/security/cacerts` 里没有。

现在写入 `$MODDIR/system/etc/security/cacerts`，由 magisk magic mount /
kernelsu overlayfs 挂给所有进程；同时用「用户证书是否可见」做探针，
overlay 没生效时自动 `mount -o bind` 兜底（只卸载 root != "/" 的自己的挂载）。

### 3. `/apex/com.android.conscrypt/cacerts`：运行时注入

`/apex` 是 init 用 **MS_PRIVATE** 挂载的，init namespace 里的 bind 不保证
出现在已运行 app 的 namespace 里。新增 `sh/inject.sh`：

* `service.sh` 起一个常驻守护；
* 对 `zygote / zygote64 / usap32 / usap64` 及它们的子进程
  （读 `/proc/<pid>/stat` 的 ppid 判断）执行：
  `nsenter --mount=/proc/<pid>/ns/mnt -- mount -o bind <store> <apex 真实路径>`；
* 用 `/proc/<pid>/root<apex>/<探针证书>` 判断是否已经生效，
  用 `/proc/<pid>/mountinfo` 判断是否已有挂载，避免重复挂；
* zygote 崩溃重启后自动重新注入。

### 4. `action.sh`（新增）

KernelSU / APatch 的 Action 按钮：不重启就重新导入、重新发布、重新注入，
并打印状态报告（证书数量、探针证书、两条路径是否可见、注入源）。

### 5. 其它

* `clean_builtin_leftovers` 不再清空 `$MODULE_SYSTEM_CERT_DIR`
  （compatible 模式现在依赖它）。
* builtin 模式不再 `rm -rf` 后只放用户证书。
* 新增 `tools/selftest.sh`：伪造 A16 目录结构跑 post-fs-data/action，
  校验 PEM 转换、权限、幂等。

## 四、怎么用（用户视角）

1. **推荐**：设置里安装抓包 CA → 重启（或点 Action）。
2. 或者：`openssl x509 -in ca.pem -noout -subject_hash_old` 得到 hash，
   把证书改名成 `<hash>.0`，`adb push` 到 `/data/local/tmp/cert/`，重启。
3. KernelSU 用户：确认目标 app 的 App Profile 没开「卸载模块」。
4. 还抓不到就查 `install.log` / Action 输出 / `status.txt`；
   若两条路径都带上了你的证书但依然握手失败，那是 app 的 SSL Pinning，不是证书问题。

## 五、版本支持范围

不是只修 Android 16。代码按 `ro.build.version.sdk` 分支，A14/15/16 走的是**同一段代码**
（futex `sdk >= 34`），矩阵测试结果：

| sdk | 系统证书来源 | APEX 发布 | legacy overlay | 用户证书格式 |
|---|---|---|---|---|
| 33 | /system | 无（跳过） | 26 张 | PEM |
| 34 | /apex | 有 | 26 张 | PEM |
| 35 | /apex | 有 | 26 张 | PEM |
| 36 | /apex | 有 | 26 张 | PEM |

也就是说 A14（34）、A15（35）、A16（36）在模块里是**完全一样**的路径：
- 合并仓库（APEX 系统证书 + 用户证书 + 自定义证书，统一 PEM）
- 写模块 overlay 发布到 `/system/etc/security/cacerts`
- tmpfs + bind 发布到 `/apex/com.android.conscrypt/cacerts`
- `service.sh` 常驻 nsenter 注入

A7-A13（sdk <= 33）没有 APEX，只走 `/system` 这一条，同样会被修好（PEM 转换 + hash 文件名）。

## 六、真机验证（Android 16）

设备：OnePlus PLF110 / Android 16（SDK 36）/ KernelSU 4.2.1（ksud 4.2.1），
模块 v1.7.0，用户证书 `dce076e2.0`（设置里安装的，磁盘上是 DER）。

| 检查项 | 结果 |
|---|---|
| 开机日志 `recorded 149 system certs` | 正确（APEX 里 149 张系统 CA） |
| 合并仓库 | 150 张，全部 PEM（`converted_der=1`） |
| `/system/etc/security/cacerts/dce076e2.0` | 存在，`-----BEGIN `，0644，`system_security_cacerts_file` |
| `/apex/com.android.conscrypt/cacerts/dce076e2.0` | 存在，PEM，SELinux 上下文同系统证书 |
| Flutter app 进程 namespace（`/proc/<pid>/root/...`） | 两条路径都能看到该证书（各 150 张） |
| zygote / usap namespace | 每条路径 150 张，注入守护进程 ppid=1（常驻） |
| KernelSU 安装（`ksud module install`） | 成功，preserve mode.conf |
| 抓包结果 | ✅ 成功抓到 Flutter app 的包 |

设备上另一个直接证据：旧版模块的日志里有一行

```
dce076e2.0 is not a der certificate, needs encoding conversion, deleting it
```

说明用户把 PEM 证书放进 `/data/local/tmp/cert` 后，**旧模块直接把它删了**
（旧逻辑只接受 DER）。这也是"证书放进去了却不生效"的直接原因之一。

## 七、注意

* 本 fork **删除了 `updateJson`**，避免自动更新把修复覆盖掉。
* 老版本 `move_custom_cert` 会删除非 DER 文件；新版本不再删除用户文件，
  只影响仓库里的副本。