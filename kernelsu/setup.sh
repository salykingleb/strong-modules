#!/system/bin/sh
# Strong Play Integrity setup for KernelSU.
# Run from the module Action button or from the WebUI Start button.
# This script does not download a keybox and it does not print key material.
#
# Put your own keybox.xml in one of these places:
#   inside this module directory
#   /sdcard/Download/keybox.xml
#   /sdcard/keybox.xml
#
# Optional local module zips, same directory, if GitHub cannot be reached:
#   zygisksu.zip            https://github.com/Dr-TSNG/ZygiskNext/releases/latest
#   playintegrityfix.zip    https://github.com/osm0sis/PlayIntegrityFork/releases/latest
#   tricky_store.zip        https://github.com/5ec1cff/TrickyStore/releases/latest
#   zygisk-assistant.zip    https://github.com/snake-4/Zygisk-Assistant/releases/latest

REBOOT=1
case "${1:-}" in
  --no-reboot) REBOOT=0 ;;
  "") ;;
  *) echo "Unknown argument: $1" >&2; echo "Usage: sh $0 [--no-reboot]" >&2; exit 2 ;;
esac

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

uid=$(id -u 2>/dev/null || echo "")
[ "$uid" = "0" ] || die "Run this as root from KernelSU."

command -v awk >/dev/null 2>&1 || die "awk is missing."

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd) || die "Cannot resolve the module directory."

find_keybox() {
  for f in \
    "$SCRIPT_DIR/keybox.xml" \
    /sdcard/Download/keybox.xml \
    /storage/emulated/0/Download/keybox.xml \
    /sdcard/keybox.xml \
    /storage/emulated/0/keybox.xml
  do
    if [ -f "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

KEYBOX_SRC=$(find_keybox) || die "keybox.xml was not found. Copy your own file into this module, or to /sdcard/Download/keybox.xml, then run again. This module does not download a keybox."

grep -q '<AndroidAttestation' "$KEYBOX_SRC" || die "keybox.xml has no AndroidAttestation root."
grep -q 'BEGIN CERTIFICATE' "$KEYBOX_SRC" || die "keybox.xml has no certificate."
grep -q 'PRIVATE KEY' "$KEYBOX_SRC" || die "keybox.xml has no private key."
if grep -q 'Software Attestation' "$KEYBOX_SRC"; then
  log "Warning: this keybox looks like a software AOSP key. That does not pass Strong."
fi

if [ -x /data/adb/ksud ]; then
  KSU=/data/adb/ksud
elif [ -x /data/adb/ksu/bin/ksud ]; then
  KSU=/data/adb/ksu/bin/ksud
elif command -v ksud >/dev/null 2>&1; then
  KSU=ksud
else
  if [ -d /data/adb/magisk ] || [ -x /data/adb/magisk/magisk ]; then
    die "Magisk is installed and ksud is missing. This module is for KernelSU only. Nothing was changed."
  fi
  die "ksud was not found. This module is for KernelSU only."
fi

log "KernelSU: $KSU"
log "Keybox file found. Its contents are not printed."

MODDIR=/data/adb/modules
UPDDIR=/data/adb/modules_update
TMP=/data/local/tmp/ksustrong
mkdir -p "$TMP" /data/adb/tricky_store "$MODDIR" || die "Cannot create work directories."
rm -f "$TMP/release.json" "$TMP/prop.tmp" "$TMP/custom.pif.prop"

NEED_REBOOT=0

prop_get() {
  file="$1"
  key="$2"
  [ -f "$file" ] || return 0
  awk -v k="$key" '
    $0 ~ /^[ \t]*#/ { next }
    index($0, k "=") == 1 {
      sub(/\r$/, "")
      print substr($0, length(k) + 2)
      exit
    }
  ' "$file"
}

set_prop() {
  file="$1"
  key="$2"
  value="$3"
  tmp="$TMP/prop.tmp"
  if [ -f "$file" ]; then
    awk -v k="$key" -v v="$value" '
      BEGIN { found = 0 }
      { sub(/\r$/, "") }
      $0 ~ /^[ \t]*#/ { print; next }
      index($0, k "=") == 1 {
        if (!found) {
          print k "=" v
          found = 1
        }
        next
      }
      { print }
      END { if (!found) print k "=" v }
    ' "$file" > "$tmp"
  else
    printf '%s=%s\n' "$key" "$value" > "$tmp"
  fi
  mv "$tmp" "$file"
}

module_present() {
  id="$1"
  [ -d "$MODDIR/$id" ] || [ -d "$UPDDIR/$id" ]
}

active_dir() {
  id="$1"
  if [ -d "$UPDDIR/$id" ]; then
    printf '%s\n' "$UPDDIR/$id"
  elif [ -d "$MODDIR/$id" ]; then
    printf '%s\n' "$MODDIR/$id"
  fi
}

module_state() {
  dir="$1"
  if [ -f "$dir/remove" ]; then
    printf '%s' "removing"
  elif [ -f "$dir/disable" ]; then
    printf '%s' "disabled"
  else
    printf '%s' "enabled"
  fi
}

ksu_disable() {
  id="$1"
  did=0
  if [ -d "$MODDIR/$id" ] && [ ! -f "$MODDIR/$id/disable" ]; then
    log "Disabling conflicting module: $id"
    "$KSU" module disable "$id" || touch "$MODDIR/$id/disable"
    did=1
  fi
  if [ -d "$UPDDIR/$id" ] && [ ! -f "$UPDDIR/$id/disable" ]; then
    log "Disabling pending install: $id"
    touch "$UPDDIR/$id/disable"
    did=1
  fi
  [ "$did" = 1 ] && NEED_REBOOT=1
  return 0
}

ksu_enable() {
  id="$1"
  changed=0
  if [ -d "$MODDIR/$id" ]; then
    if [ -f "$MODDIR/$id/remove" ]; then
      log "Undoing uninstall: $id"
      "$KSU" module undo-uninstall "$id" || rm -f "$MODDIR/$id/remove"
      changed=1
    fi
    if [ -f "$MODDIR/$id/disable" ]; then
      log "Enabling: $id"
      "$KSU" module enable "$id" || rm -f "$MODDIR/$id/disable"
      changed=1
    fi
  fi
  if [ -d "$UPDDIR/$id" ]; then
    if [ -f "$UPDDIR/$id/remove" ] || [ -f "$UPDDIR/$id/disable" ]; then
      rm -f "$UPDDIR/$id/remove" "$UPDDIR/$id/disable"
      log "Cleared a block on the pending install: $id"
      changed=1
    fi
  fi
  [ "$changed" = 1 ] && NEED_REBOOT=1
  return 0
}

is_conflict() {
  id="$1"
  name="$2"
  case "$id" in
    ksustrong|playintegrityfix|tricky_store|zygisk-assistant|zygisksu|rezygisk|neozygisk)
      return 1
      ;;
  esac
  case "$id" in
    shamiko|safetynet-fix|safetynetfix|magiskhidepropsconf|playcurl|playcurlnext|playcurl_next|yurikey|alwaysstrong|pifs|playintegrityfixinject|trickyaddon|trickystoreaddon|TA_utl)
      return 0
      ;;
  esac
  case "$name" in
    *Shamiko*|*shamiko*|*SafetyNet*|*safetynet*|*PlayCurl*|*playcurl*|*YuriKey*|*Yurikey*|*yurikey*|*TrickyAddon*|*Tricky*Addon*|*trickyaddon*|*tricky*addon*|*MagiskHide*|*magiskhide*|*Magisk*Hide*)
      return 0
      ;;
  esac
  return 1
}

download_latest_zip() {
  repo="$1"
  dest="$2"
  json="$TMP/release.json"
  rm -f "$json" "$dest"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -A ksustrong -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$repo/releases/latest" -o "$json" || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$json" "https://api.github.com/repos/$repo/releases/latest" || return 1
  else
    return 1
  fi
  urls=$(tr ',' '\n' < "$json" | sed -n 's/.*"browser_download_url": *"\([^"]*\.zip\)".*/\1/p' | grep '/releases/download/')
  url=""
  fallback=""
  oldifs=$IFS
  IFS='
'
  set -f
  for u in $urls; do
    [ -n "$u" ] || continue
    base=${u##*/}
    low=$(printf '%s' "$base" | tr 'A-Z' 'a-z')
    case "$low" in
      *debug*|*source*) continue ;;
    esac
    case "$low" in
      *release*) url=$u; break ;;
    esac
    [ -z "$fallback" ] && fallback=$u
  done
  set +f
  IFS=$oldifs
  [ -n "$url" ] || url=$fallback
  [ -n "$url" ] || return 1
  log "Downloading $url"
  if command -v curl >/dev/null 2>&1; then
    curl -fL -A ksustrong -o "$dest" "$url" || return 1
  else
    wget -q -O "$dest" "$url" || return 1
  fi
  [ -s "$dest" ] || return 1
  return 0
}

install_zip() {
  id="$1"
  repo="$2"
  force="${3:-0}"
  if [ "$force" != "1" ] && module_present "$id"; then
    log "Already installed: $id"
    ksu_enable "$id"
    return 0
  fi
  if [ "$force" = "1" ]; then
    log "Reinstalling: $id ($repo)"
  else
    log "Missing module $id. Installing $repo"
  fi
  stage="$TMP/$id.zip"
  if ! download_latest_zip "$repo" "$stage"; then
    if [ -f "$SCRIPT_DIR/$id.zip" ]; then
      log "Download failed. Using the local archive: $SCRIPT_DIR/$id.zip"
      cp -f "$SCRIPT_DIR/$id.zip" "$stage" || die "Could not copy $id.zip into the temp directory."
    else
      die "Could not download $repo. Put the official zip in this module directory as $id.zip and run again. Page: https://github.com/$repo/releases/latest"
    fi
  fi
  # /data/local/tmp stays visible after ksud switches mount namespace. /sdcard often does not.
  "$KSU" module install "$stage" || die "ksud could not install $id"
  module_present "$id" || die "After install, $id is not in $MODDIR or $UPDDIR"
  ksu_enable "$id"
  NEED_REBOOT=1
  return 0
}

log "Installed modules:"
found_any=0
for base in "$MODDIR" "$UPDDIR"; do
  for prop in "$base"/*/module.prop; do
    [ -f "$prop" ] || continue
    found_any=1
    id=$(prop_get "$prop" id)
    name=$(prop_get "$prop" name)
    ver=$(prop_get "$prop" version)
    dir=$(dirname "$prop")
    where="active"
    [ "$base" = "$UPDDIR" ] && where="after reboot"
    log "  $(module_state "$dir")  [$where]  ${id:-?}  ${name:-?}  ${ver:-?}"
  done
done
[ "$found_any" = 1 ] || log "  none"

log "Looking for conflicting modules."
for base in "$MODDIR" "$UPDDIR"; do
  for prop in "$base"/*/module.prop; do
    [ -f "$prop" ] || continue
    id=$(prop_get "$prop" id)
    name=$(prop_get "$prop" name)
    [ -n "$id" ] || continue
    if is_conflict "$id" "$name"; then
      ksu_disable "$id"
    fi
    case "$id$name" in
      *lsposed*|*LSPosed*)
        log "Leaving LSPosed ($id) enabled. It can break Strong."
        ;;
    esac
  done
done

if ! module_present zygisksu; then
  install_zip zygisksu Dr-TSNG/ZygiskNext
fi
ksu_disable rezygisk
ksu_disable neozygisk
ksu_enable zygisksu
ZYGISK_ID=zygisksu
module_present "$ZYGISK_ID" || die "ZygiskNext is missing. KernelSU needs it so Play Integrity Fork can inject into Play Services while Zygisk Assistant hides root."
log "Zygisk: $ZYGISK_ID"

PIF_DIR=$(active_dir playintegrityfix)
PIF_AUTHOR=""
if [ -n "$PIF_DIR" ]; then
  PIF_AUTHOR=$(prop_get "$PIF_DIR/module.prop" author)
fi
case "$PIF_AUTHOR" in
  *osm0sis*)
    log "Play Integrity Fork is already the osm0sis build."
    ksu_enable playintegrityfix
    ;;
  "")
    if [ -n "$PIF_DIR" ]; then
      log "playintegrityfix has no osm0sis author. Reinstalling Play Integrity Fork."
      install_zip playintegrityfix osm0sis/PlayIntegrityFork 1
    else
      install_zip playintegrityfix osm0sis/PlayIntegrityFork
    fi
    ;;
  *)
    log "playintegrityfix author is '$PIF_AUTHOR'. Reinstalling the osm0sis build."
    install_zip playintegrityfix osm0sis/PlayIntegrityFork 1
    ;;
esac
PIF_DIR=$(active_dir playintegrityfix)
PIF_AUTHOR=""
if [ -n "$PIF_DIR" ]; then
  PIF_AUTHOR=$(prop_get "$PIF_DIR/module.prop" author)
fi
case "$PIF_AUTHOR" in
  *osm0sis*) ;;
  *) die "Play Integrity Fork is installed, but the author is not osm0sis (${PIF_AUTHOR:-empty}). Use the official osm0sis zip." ;;
esac
module_present playintegrityfix || die "Play Integrity Fork is not installed."

install_zip tricky_store 5ec1cff/TrickyStore
module_present tricky_store || die "Tricky Store is not installed."

ZA_ID=""
if module_present zygisk-assistant; then
  ZA_ID=zygisk-assistant
else
  for base in "$UPDDIR" "$MODDIR"; do
    for prop in "$base"/*/module.prop; do
      [ -f "$prop" ] || continue
      id=$(prop_get "$prop" id)
      name=$(prop_get "$prop" name)
      case "$name" in
        *Zygisk*Assistant*) ZA_ID="$id"; break ;;
      esac
    done
    [ -n "$ZA_ID" ] && break
  done
fi
if [ -z "$ZA_ID" ]; then
  install_zip zygisk-assistant snake-4/Zygisk-Assistant
  ZA_ID=zygisk-assistant
fi
ksu_enable "$ZA_ID"
module_present "$ZA_ID" || die "Zygisk Assistant is not installed."
log "Root hide: $ZA_ID"

KEYBOX_DEST=/data/adb/tricky_store/keybox.xml
src_real="$SCRIPT_DIR/$(basename "$KEYBOX_SRC")"
if [ "$src_real" = "$KEYBOX_DEST" ]; then
  log "keybox.xml is already in /data/adb/tricky_store."
else
  log "Copying keybox.xml to /data/adb/tricky_store/keybox.xml"
  if [ -f "$KEYBOX_DEST" ]; then
    cp -f "$KEYBOX_DEST" /data/adb/tricky_store/keybox.xml.bak.module
    chmod 600 /data/adb/tricky_store/keybox.xml.bak.module 2>/dev/null || true
  fi
  umask 077
  cat "$KEYBOX_SRC" > "$KEYBOX_DEST" || die "Could not write keybox.xml"
  umask 022
fi
chmod 600 "$KEYBOX_DEST" || die "Could not restrict keybox.xml permissions."
chown 0:0 "$KEYBOX_DEST" 2>/dev/null || true
chcon u:object_r:adb_data_file:s0 "$KEYBOX_DEST" 2>/dev/null || true
grep -q 'BEGIN CERTIFICATE' "$KEYBOX_DEST" || die "The written keybox.xml cannot be read."
src_size=$(wc -c < "$KEYBOX_SRC" | tr -d ' \t\r\n')
dst_size=$(wc -c < "$KEYBOX_DEST" | tr -d ' \t\r\n')
[ "$src_size" = "$dst_size" ] || die "The written keybox.xml size does not match the source."

label_file() {
  chmod 644 "$1" 2>/dev/null || true
  chown 0:0 "$1" 2>/dev/null || true
  chcon u:object_r:adb_data_file:s0 "$1" 2>/dev/null || true
}

cat > /data/adb/tricky_store/target.txt <<'EOF'
android
com.android.vending
com.google.android.gms
com.google.android.gsf
io.github.vvb2060.keyattestation
gr.nikolasspyr.integritycheck
EOF
label_file /data/adb/tricky_store/target.txt
log "target.txt written. The ! and ? suffixes are not used."

WORK="$TMP/custom.pif.prop"
write_bluejay() {
  cat > "$WORK" <<'EOF'
# Build Fields
MANUFACTURER=Google
MODEL=Pixel 6a
FINGERPRINT=google/bluejay_beta/bluejay:CANARY/ZP11.260918.007/16484274:user/release-keys
BRAND=google
PRODUCT=bluejay_beta
DEVICE=bluejay
RELEASE=CANARY
ID=ZP11.260918.007
INCREMENTAL=16484274
TYPE=user
TAGS=release-keys
SECURITY_PATCH=2026-10-05
DEVICE_INITIAL_SDK_INT=32

# System Properties
*.build.id=ZP11.260918.007
*.security_patch=2026-10-05
*api_level=32

# Advanced Settings
spoofBuild=1
spoofProps=1
spoofProvider=0
spoofSignature=0
spoofVendingFinger=0
spoofVendingSdk=0
verboseLogs=0

# Canary released 2026-10-07. Estimated expiry 2026-11-18.
# Pixel 6a real first_api_level is 32.
EOF
  log "Wrote the Pixel 6a fingerprint. Its real first_api_level is 32."
  log "This canary was released on 2026-10-07. Estimated expiry: 2026-11-18."
}

PIF_DIR=$(active_dir playintegrityfix)
AUTOPIF=""
if [ -n "$PIF_DIR" ] && [ -f "$PIF_DIR/autopif4.sh" ]; then
  AUTOPIF="$PIF_DIR/autopif4.sh"
fi

pull_pif_to_work() {
  src=""
  if [ -n "$AUTOPIF" ] && [ -s "$(dirname "$AUTOPIF")/custom.pif.prop" ]; then
    src="$(dirname "$AUTOPIF")/custom.pif.prop"
  elif [ -s "$MODDIR/playintegrityfix/custom.pif.prop" ]; then
    src="$MODDIR/playintegrityfix/custom.pif.prop"
  elif [ -s "$UPDDIR/playintegrityfix/custom.pif.prop" ]; then
    src="$UPDDIR/playintegrityfix/custom.pif.prop"
  else
    return 1
  fi
  cp -f "$src" "$WORK"
}

if [ -n "$AUTOPIF" ] && grep -q 'caiman)' "$AUTOPIF"; then
  log "autopif4 knows per-device first_api_level values. Fetching a current print."
  if sh "$AUTOPIF" --strong; then
    pull_pif_to_work || write_bluejay
  else
    log "autopif4 failed. Using the verified Pixel 6a print."
    write_bluejay
  fi
else
  log "This Play Integrity Fork has no per-device first_api_level table. Using Pixel 6a."
  write_bluejay
fi
[ -s "$WORK" ] || write_bluejay

DEVICE_NAME=$(prop_get "$WORK" DEVICE)
API_NOW=$(prop_get "$WORK" '*api_level')
fallback=0
case "$DEVICE_NAME" in
  yogi) fallback=1 ;;
  comet|stallion)
    [ "$API_NOW" = "32" ] && fallback=1
    ;;
esac
if [ "$fallback" = 1 ]; then
  log "$DEVICE_NAME with api_level ${API_NOW:-empty} does not pass Strong. Falling back to Pixel 6a."
  write_bluejay
  DEVICE_NAME=$(prop_get "$WORK" DEVICE)
  API_NOW=$(prop_get "$WORK" '*api_level')
fi

WANT_API=""
case "$DEVICE_NAME" in
  bluejay) WANT_API=32 ;;
  panther|cheetah|lynx|felix|tangorpro) WANT_API=33 ;;
  shiba|husky|akita|tokay|caiman|komodo|comet) WANT_API=34 ;;
  tegu) WANT_API=35 ;;
  frankel|blazer|mustang|rango) WANT_API=36 ;;
esac
if [ -n "$WANT_API" ] && [ "$API_NOW" != "$WANT_API" ]; then
  log "Setting api_level $WANT_API for $DEVICE_NAME. Previous value: ${API_NOW:-empty}."
  set_prop "$WORK" '*api_level' "$WANT_API"
  set_prop "$WORK" DEVICE_INITIAL_SDK_INT "$WANT_API"
fi

set_prop "$WORK" spoofBuild 1
set_prop "$WORK" spoofProps 1
set_prop "$WORK" spoofProvider 0
set_prop "$WORK" spoofSignature 0
set_prop "$WORK" spoofVendingFinger 0
set_prop "$WORK" spoofVendingSdk 0
set_prop "$WORK" verboseLogs 0
got=$(prop_get "$WORK" spoofProvider)
[ "$got" = "0" ] || die "spoofProvider must stay 0, or attestation bypasses the keybox."

PATCH=$(prop_get "$WORK" SECURITY_PATCH)
[ -n "$PATCH" ] || die "The fingerprint has no SECURITY_PATCH."
case "$PATCH" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
    DASHED=$PATCH
    COMPACT=$(printf '%s' "$PATCH" | tr -d '-')
    ;;
  [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])
    COMPACT=$PATCH
    DASHED=$(printf '%s-%s-%s' "$(printf '%s' "$PATCH" | cut -c1-4)" "$(printf '%s' "$PATCH" | cut -c5-6)" "$(printf '%s' "$PATCH" | cut -c7-8)")
    ;;
  *) die "SECURITY_PATCH has an unexpected form: $PATCH" ;;
esac
set_prop "$WORK" SECURITY_PATCH "$DASHED"
set_prop "$WORK" '*.security_patch' "$DASHED"

synced=0
for base in "$MODDIR" "$UPDDIR"; do
  if [ -d "$base/playintegrityfix" ]; then
    cp -f "$WORK" "$base/playintegrityfix/custom.pif.prop"
    label_file "$base/playintegrityfix/custom.pif.prop"
    synced=1
    log "Fingerprint written: $base/playintegrityfix/custom.pif.prop"
  fi
done
[ "$synced" = 1 ] || die "There is no playintegrityfix directory to write custom.pif.prop into."

printf '%s\n' "$COMPACT" > /data/adb/tricky_store/security_patch.txt
label_file /data/adb/tricky_store/security_patch.txt
log "security_patch.txt = $COMPACT"
log "tee_status was left unchanged."

if [ -f "$MODDIR/zygisksu/bin/zygiskd" ]; then
  chmod 755 "$MODDIR/zygisksu/bin/zygiskd" 2>/dev/null || true
  log "ZygiskNext: enforce-denylist disabled"
  if "$MODDIR/zygisksu/bin/zygiskd" enforce-denylist disabled; then
    log "Enforce DenyList is off, so Play Integrity Fork can still inject into Play Services."
  else
    log "The ZygiskNext daemon did not accept the command yet. After boot, leave Enforce DenyList disabled."
  fi
elif [ -f "$MODDIR/zygisksu/bin/zygisk-ctl" ]; then
  chmod 755 "$MODDIR/zygisksu/bin/zygisk-ctl" 2>/dev/null || true
  log "ZygiskNext: enforce-denylist disabled"
  "$MODDIR/zygisksu/bin/zygisk-ctl" enforce-denylist disabled || log "After boot, leave Enforce DenyList disabled."
else
  log "zygiskd is not in the active module yet. After reboot, leave Enforce DenyList disabled."
fi

if "$KSU" feature set kernel_umount 1 >/dev/null 2>&1; then
  log "Kernel feature kernel_umount is enabled."
else
  log "kernel_umount was not changed. That is normal on a non-GKI kernel."
fi
log "In the KernelSU manager, leave Umount modules enabled by default."
log "Do not grant root to com.google.android.gms."

if [ "$NEED_REBOOT" = 0 ] && [ -f "$MODDIR/playintegrityfix/killpi.sh" ]; then
  log "Restarting DroidGuard and the Play Store."
  sh "$MODDIR/playintegrityfix/killpi.sh" || true
fi

rm -f "$TMP/release.json" "$TMP"/*.zip "$WORK" 2>/dev/null || true

log "Done."
log "Keybox: /data/adb/tricky_store/keybox.xml"
log "Fingerprint: custom.pif.prop inside playintegrityfix. spoofProvider=0."
log "Patch: /data/adb/tricky_store/security_patch.txt"
if [ "$NEED_REBOOT" = 1 ]; then
  if [ "$REBOOT" = 1 ]; then
    log "New modules were installed. Rebooting."
    sync
    sleep 2
    reboot
  else
    log "Reboot before Strong can pass. New modules load on the next boot."
  fi
else
  log "Open Play Integrity API Checker and tap CHECK."
  log "BASIC, DEVICE, and STRONG should pass."
fi
