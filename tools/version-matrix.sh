#!/bin/sh
# 版本矩阵测试：同一套脚本在 sdk=33/34/35/36 下的行为
set -u
MODSRC=$(cd "$(dirname "$0")/.." && pwd)
run_case() {
  SDK=$1
  ROOT=/tmp/mc-matrix-$SDK
  rm -rf "$ROOT"; mkdir -p "$ROOT/mod" "$ROOT/system" "$ROOT/apex" "$ROOT/temp" \
    "$ROOT/user0/cacerts-added" "$ROOT/custom" "$ROOT/stubs"

  i=1; while [ $i -le 25 ]; do
    openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -out "$ROOT/system/s$i.pem" \
      -days 30 -subj "/CN=System CA $i/O=T" 2>/dev/null; i=$((i+1))
  done
  for f in "$ROOT/system"/*.pem; do h=$(openssl x509 -in "$f" -noout -subject_hash_old); mv "$f" "$ROOT/system/$h.0"; done
  i=1; while [ $i -le 25 ]; do
    openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -out "$ROOT/apex/a$i.pem" \
      -days 30 -subj "/CN=Apex CA $i/O=T" 2>/dev/null; i=$((i+1))
  done
  for f in "$ROOT/apex"/*.pem; do h=$(openssl x509 -in "$f" -noout -subject_hash_old); mv "$f" "$ROOT/apex/$h.0"; done

  openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -out "$ROOT/u.pem" -days 30 -subj "/CN=User CA/O=T" 2>/dev/null
  UH=$(openssl x509 -in "$ROOT/u.pem" -noout -subject_hash_old)
  openssl x509 -in "$ROOT/u.pem" -outform der -out "$ROOT/user0/cacerts-added/$UH.0"

  printf '#!/bin/sh\ncase "$1" in ro.build.version.sdk) echo %s;; sys.boot_completed) echo 1;; *) echo "";; esac\n' "$SDK" > "$ROOT/stubs/getprop"
  printf '#!/bin/sh\necho Permissive\n' > "$ROOT/stubs/getenforce"
  for x in chcon chown pidof nsenter mount umount; do printf '#!/bin/sh\nexit 0\n' > "$ROOT/stubs/$x"; done
  chmod +x "$ROOT/stubs/"*

  cp -r "$MODSRC/sh" "$ROOT/mod/"; cp "$MODSRC/post-fs-data.sh" "$ROOT/mod/"
  echo "mode=compatible" > "$ROOT/mod/mode.conf"

  PATH="$ROOT/stubs:$PATH" \
  SYSTEM_CERT_DIR="$ROOT/system" APEX_CONSCRYPT_DIR="$ROOT/apex" USER_CERT_ROOT="$ROOT" \
  USER_CERT_DIR="$ROOT/user0/cacerts-added" CUSTOM_CERT_DIR="$ROOT/custom" TEMP_DIR="$ROOT/temp" \
  MODDIR="$ROOT/mod" sh "$ROOT/mod/post-fs-data.sh"

  LOG="$ROOT/mod/install.log"
  echo "===== sdk=$SDK ====="
  echo "  store=$(ls -1A "$ROOT/mod/certificates"|wc -l)  user_cert_in_store=$([ -f "$ROOT/mod/certificates/$UH.0" ] && head -c 11 "$ROOT/mod/certificates/$UH.0" | grep -q BEGIN && echo PEM || echo MISSING)"
  echo "  legacy_overlay_files=$(ls -1A "$ROOT/mod/system/etc/security/cacerts" 2>/dev/null|wc -l)  user_cert=$( [ -f "$ROOT/mod/system/etc/security/cacerts/$UH.0" ] && echo yes || echo no )"
  echo "  apex_overlay_files=$(ls -1A "$ROOT/mod/apex/com.android.conscrypt/cacerts" 2>/dev/null|wc -l)"
  echo "  seed_source=$(grep "seed store from" "$LOG" | sed "s/.*seed store from //")"
  echo "  apex_install=$(grep -c "install apex store" "$LOG")  apex_mounts=$(grep -c "mount bind .*apex" "$LOG")  legacy_bind=$(grep -c "mount bind .*system/etc/security/cacerts" "$LOG")  legacy_ok=$(grep -c "legacy store OK" "$LOG")"
}
run_case 33
run_case 34
run_case 35
run_case 36