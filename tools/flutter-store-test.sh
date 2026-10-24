#!/bin/sh
# ============================================================================
# Flutter/Dart 端到端验证
# ----------------------------------------------------------------------------
# 用真实 Dart VM（libflutter.so 里用的是同一套 Dart BoringSSL 代码路径）
# 验证模块生成的证书仓库能否被 Flutter 信任：
#   1. 生成一个"代理 CA"（DER 形式放进 Android 用户证书目录，模拟设置里安装）
#   2. 跑模块 post-fs-data 生成合并仓库
#   3. Dart 用 --root-certs-cache=<仓库> 去连由该 CA 签发的 HTTPS 服务
#   4. 期望：仓库目录 -> 成功；用户证书目录(DER) -> 失败
# 需要：openssl、python3、Dart SDK（DART_BIN 环境变量，默认 /tmp/dartsdk/dart-sdk/bin/dart）
# ============================================================================
set -u
ROOT=${ROOT:-/tmp/mc-flutter-test}
MODSRC=$(cd "$(dirname "$0")/.." && pwd)
DART_BIN=${DART_BIN:-/tmp/dartsdk/dart-sdk/bin/dart}
PORT=${PORT:-8455}

if [ ! -x "$DART_BIN" ]; then
    echo "SKIP: 找不到 Dart SDK ($DART_BIN)"
    exit 0
fi

rm -rf "$ROOT"
mkdir -p "$ROOT/mod" "$ROOT/system" "$ROOT/apex" "$ROOT/temp" \
         "$ROOT/user0/cacerts-added" "$ROOT/custom" "$ROOT/stubs"

# ---- 系统证书（假装是系统自带的 25 张）----
i=1
while [ $i -le 25 ]; do
    openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null \
        -out "$ROOT/system/ca-$i.pem" -days 30 -subj "/CN=System CA $i/O=T" 2>/dev/null
    i=$((i + 1))
done
for f in "$ROOT/system"/*.pem; do
    h=$(openssl x509 -in "$f" -noout -subject_hash_old)
    mv "$f" "$ROOT/system/$h.0"
done

# ---- 代理 CA + 服务器证书 ----
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$ROOT/ca.key" -out "$ROOT/ca.pem" \
    -days 30 -subj "/CN=My Proxy CA/O=Mitm" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout "$ROOT/srv.key" -out "$ROOT/srv.csr" \
    -subj "/CN=localhost" 2>/dev/null
printf "subjectAltName=IP:127.0.0.1,DNS:localhost\n" >"$ROOT/ext.cnf"
openssl x509 -req -in "$ROOT/srv.csr" -CA "$ROOT/ca.pem" -CAkey "$ROOT/ca.key" \
    -CAcreateserial -out "$ROOT/srv.pem" -days 30 -extfile "$ROOT/ext.cnf" 2>/dev/null

# Android 用户证书目录：DER + hash 文件名
CH=$(openssl x509 -in "$ROOT/ca.pem" -noout -subject_hash_old)
openssl x509 -in "$ROOT/ca.pem" -outform der -out "$ROOT/user0/cacerts-added/$CH.0"

# ---- 桩 ----
cat >"$ROOT/stubs/getprop" <<'EOF'
#!/bin/sh
case "$1" in
    ro.build.version.sdk) echo 36 ;;
    sys.boot_completed) echo 1 ;;
    *) echo "" ;;
esac
EOF
cat >"$ROOT/stubs/getenforce" <<'EOF'
#!/bin/sh
echo Permissive
EOF
for n in chcon chown pidof nsenter; do
    printf '#!/bin/sh\nexit 0\n' >"$ROOT/stubs/$n"
done
printf '#!/bin/sh\nexit 0\n' >"$ROOT/stubs/mount"
printf '#!/bin/sh\nexit 0\n' >"$ROOT/stubs/umount"
chmod +x "$ROOT/stubs/"*

# ---- 模块 ----
cp -r "$MODSRC/sh" "$ROOT/mod/"
cp "$MODSRC/post-fs-data.sh" "$ROOT/mod/"
echo "mode=compatible" >"$ROOT/mod/mode.conf"

PATH="$ROOT/stubs:$PATH"
export PATH
SYSTEM_CERT_DIR="$ROOT/system"
APEX_CONSCRYPT_DIR="$ROOT/apex"
USER_CERT_ROOT="$ROOT"
USER_CERT_DIR="$ROOT/user0/cacerts-added"
CUSTOM_CERT_DIR="$ROOT/custom"
TEMP_DIR="$ROOT/temp"
MODDIR="$ROOT/mod"
export SYSTEM_CERT_DIR APEX_CONSCRYPT_DIR USER_CERT_ROOT USER_CERT_DIR CUSTOM_CERT_DIR TEMP_DIR MODDIR

sh "$ROOT/mod/post-fs-data.sh"
STORE="$ROOT/mod/certificates"

# ---- 起 HTTPS 服务 ----
python3 - "$ROOT" "$PORT" <<'PY' &
import http.server, ssl, sys, os
root, port = sys.argv[1], int(sys.argv[2])
os.chdir(root)
httpd = http.server.HTTPServer(('127.0.0.1', port), http.server.SimpleHTTPRequestHandler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(os.path.join(root, 'srv.pem'), os.path.join(root, 'srv.key'))
httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
PY
sleep 2

cat >"$ROOT/client.dart" <<'DART'
import 'dart:io';
Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? args[0] : '8455';
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('https://127.0.0.1:' + port + '/'));
    final resp = await req.close();
    print('RESULT OK ' + resp.statusCode.toString());
  } catch (e) {
    print('RESULT FAIL ' + e.toString());
  }
  client.close(force: true);
}
DART

echo "---- Dart: 用户证书目录(Android 原生 DER) ----"
"$DART_BIN" --root-certs-cache="$ROOT/user0/cacerts-added" "$ROOT/client.dart" "$PORT" 2>&1 | tail -1
echo "---- Dart: 模块合并仓库(PEM) ----"
"$DART_BIN" --root-certs-cache="$STORE" "$ROOT/client.dart" "$PORT" 2>&1 | tail -1

pkill -f "mc-flutter-test" 2>/dev/null
wait 2>/dev/null
exit 0
