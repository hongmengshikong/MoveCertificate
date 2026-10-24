##########################################################################################
#
# Magisk Module Installer Script
#
##########################################################################################

SKIPUNZIP=0

print_modname() {
  ui_print " "
  ui_print "*******************************"
  ui_print " 支持安卓 7 - 16 证书迁移"
  ui_print " 已修复 Flutter / Dart 抓包"
  ui_print "*******************************"
  ui_print " "
}

on_install() {

  F_TARGETDIR="$MODPATH/system/etc/security/cacerts/"
  D_CERTIFICATE="$MODPATH/certificates"
  APEX_CONSCRYPT_DIR="$MODPATH/apex/com.android.conscrypt/cacerts"

  # 自定义证书目录（用户 adb push 到这里）
  D_TMP_CERT=/data/local/tmp/cert

  if [ -f "$D_TMP_CERT" ]; then
    ui_print "- ${D_TMP_CERT} found"
  else
    mkdir -p -m 777 "$D_TMP_CERT"
  fi

  mkdir -p -m 755 "$F_TARGETDIR"
  mkdir -p -m 755 "$APEX_CONSCRYPT_DIR"
  mkdir -p -m 755 "$D_CERTIFICATE"
  mkdir -p -m 755 /data/misc/user/0/cacerts-added

  APEX_VER_NAME=$(basename "$(find /apex -type d -name 'com.android.conscrypt@*' 2>/dev/null | head -n1)")
  if [ -n "$APEX_VER_NAME" ]; then
    mkdir -p -m 755 "$MODPATH/apex/$APEX_VER_NAME/cacerts"
  fi

  # 运行模式配置：升级时保留用户原来的选择
  MODE_CONF="$MODPATH/mode.conf"
  OLD_MODE_CONF="/data/adb/modules/MoveCertificate/mode.conf"
  if [ ! -f "$MODE_CONF" ] && [ -f "$OLD_MODE_CONF" ]; then
    cp "$OLD_MODE_CONF" "$MODE_CONF"
    ui_print "- Preserved existing mode.conf ($(cat "$MODE_CONF"))"
  fi
  if [ ! -f "$MODE_CONF" ]; then
    echo "mode=compatible" > "$MODE_CONF"
    ui_print "- Created default mode.conf (compatible mode)"
  fi

  # 保留已识别证书名称缓存
  OLD_CERT_NAMES="/data/adb/modules/MoveCertificate/cert_names.json"
  if [ -f "$OLD_CERT_NAMES" ]; then
    cp "$OLD_CERT_NAMES" "$MODPATH/cert_names.json"
    ui_print "- Preserved existing cert_names.json"
  fi

  ui_print "- 证书目录: /data/local/tmp/cert (重启后自动导入)"
  ui_print "- Flutter 需要 <hash>.0 命名的 PEM 证书，模块会自动把 DER 转成 PEM"
}

print_modname
on_install