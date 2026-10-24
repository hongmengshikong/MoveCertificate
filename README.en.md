# [MoveCertificate](https://github.com/ys1231/MoveCertificate)

[中文](README.md) | [Türkçe](README.tr.md)

A `Magisk/KernelSU/APatch` module that moves user certificates into the system trust store.
Supports `Android 7-16`, including `Android 16` with `Flutter/Dart` apps.

> **This fork (v1.7.0-flutter16) fixes "Flutter apps can't be intercepted on Android 16".**
> See [FORK-FIX.md](FORK-FIX.md) for the full root-cause analysis.

# Why Flutter could not be intercepted before

| Who reads it | Directory | Accepted format |
|---|---|---|
| Java / Conscrypt | `/apex/com.android.conscrypt/cacerts` (A14+), fallback `/system/etc/security/cacerts` | PEM or DER |
| **Flutter / Dart (BoringSSL in libflutter.so)** | old engines: `/system/etc/security/cacerts` only; new engines: the APEX dir first | **PEM only**, file name must be `<subject_hash_old>.0` |

Dart calls `SSL_CTX_load_verify_locations(ctx, NULL, dir)` and BoringSSL registers that directory with
`X509_LOOKUP_add_dir(lookup, path, X509_FILETYPE_PEM)` — i.e. a **hashed directory of PEM files**.
DER files (what Android writes into `/data/misc/user/0/cacerts-added`) are silently ignored, and files whose
name is not the subject hash are never looked up.

The module now:

1. merges *system + user + custom* certificates into one store,
2. converts everything to **PEM** (keeping the `<hash>.0` name),
3. publishes it to `/system/etc/security/cacerts` through the module overlay (visible to every app namespace),
4. publishes it to `/apex/com.android.conscrypt/cacerts` through a tmpfs bind,
5. keeps a `service.sh` supervisor that `nsenter`s the APEX directory into zygote / usap / already-running app
   mount namespaces (on Android 14/15/16 `/apex` is mounted with MS_PRIVATE, so bind mounts made in init's
   namespace do not always reach running apps).

# Usage

## 1) Install through system settings (recommended)

Settings → Security → Encryption & credentials → Install a certificate → CA certificate, pick the proxy CA,
then **reboot** (or press the module's **Action** button in KernelSU/APatch).

Android stores it as `/data/misc/user/0/cacerts-added/<hash>.0` in DER; the module converts it to PEM
automatically — you don't have to convert anything manually.

## 2) Push to `/data/local/tmp/cert` (for many devices / baked-in CA)

The directory is re-imported on every boot **and** whenever you press Action.

```shell
openssl x509 -in cacert.pem -noout -subject_hash_old      # e.g. c8750f0d
cp cacert.pem c8750f0d.0                                  # PEM is best; DER also accepted
adb push c8750f0d.0 /data/local/tmp/cert/
# then reboot (or press Action)
```

Common reasons it "did nothing":

1. no reboot / no Action press — the directory is only imported at boot or on Action;
2. wrong file name — it must be `<subject_hash_old>.0`, otherwise Flutter will never find it;
3. wrong format — older versions asked for DER, but **Flutter only parses PEM** (this build accepts both and
   converts DER → PEM);
4. the file isn't a CA certificate.

## WebUI

The module ships a WebUI (open it from the KernelSU / APatch module page). v1.7.1 redesigned it:

<img src="README.assets/webui-certs.png" width="260" alt="Certificates"> <img src="README.assets/webui-mode.png" width="260" alt="Mode">

* **Certificates** — live list with an Active / Inactive pill and a one-tap delete (confirm sheet)
* **Status** — mode, store size, probe result for `/system` and APEX paths, injected process count
* **Mode** — compatible / built-in segmented switch (writes `mode.conf`, reboot to apply)
* **Log** — reads `install.log`
* **Settings** — language (中文 / English / Türkçe / follow system, bottom sheet), appearance, about

## KernelSU / APatch

If the target app has **"Umount modules"** enabled in its App Profile, the app cannot see the module mounts and
interception will always fail. Disable it for that app (or globally).

# Verification performed

Real Dart VM (same BoringSSL code path as `libflutter.so`), connecting to a local HTTPS server signed by the
test CA:

| CA directory content | Result |
|---|---|
| `<hash>.0` + DER (raw Android user cert) | ❌ `CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate` |
| `<hash>.0` + PEM (converted by this module) | ✅ HTTP 200 |
| PEM with a non-hash file name | ❌ not found |

If a Flutter app still can't be intercepted after this, the app is doing **SSL pinning** inside
`libflutter.so` — that is a different problem (hook `ssl_verify_cert_chain` / `SSL_CTX_set_custom_verify`).

# Build

```shell
./buildzip.sh all    # builds the WebUI too (node/npm required)
./buildzip.sh sweb   # skip the WebUI build
```

# Test Results
![2024-02-19_01.27.27](README.assets/2024-02-19_01.27.27.png)

# References
- http://www.zhuoyue360.com/crack/60.html
- https://topjohnwu.github.io/Magisk/guides.html#boot-scripts
- https://github.com/Magisk-Modules-Repo/movecert
- https://book.hacktricks.xyz/v/cn/mobile-pentesting/android-app-pentesting/install-burp-certificate#android-14-zhi-hou
- https://kernelsu.org/zh_CN/guide/module.html
- https://github.com/dart-lang/sdk/blob/main/runtime/bin/security_context_linux.cc
- https://github.com/google/boringssl/blob/master/crypto/x509/x509_d2.cc