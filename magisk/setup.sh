#!/system/bin/sh
# Strong Play Integrity for Magisk.
# Does not download a keybox and does not print key material.
#
# Put your own file in one of these places:
#   keybox.xml or Keybox.xml in this module directory
#   /sdcard/Download/keybox.xml or Keybox.xml
#   /sdcard/keybox.xml or Keybox.xml
# An existing /data/adb/tricky_store/keybox.xml is also accepted.
#
# Optional local zips next to this script, if GitHub cannot be reached:
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
[ "$uid" = "0" ] || die "Run this as root through Magisk."

command -v awk >/dev/null 2>&1 || die "awk is not available on this phone."

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd) || die "Could not find the module directory."

find_keybox() {
  for f in \
    "$SCRIPT_DIR/keybox.xml" \
    "$SCRIPT_DIR/Keybox.xml" \
    /sdcard/Download/keybox.xml \
    /sdcard/Download/Keybox.xml \
    /storage/emulated/0/Download/keybox.xml \
    /storage/emulated/0/Download/Keybox.xml \
    /sdcard/keybox.xml \
    /sdcard/Keybox.xml \
    /storage/emulated/0/keybox.xml \
    /storage/emulated/0/Keybox.xml \
    /data/adb/tricky_store/keybox.xml
  do
    if [ -f "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

KEYBOX_SRC=$(find_keybox) || die "No keybox found. Put keybox.xml or Keybox.xml in the module zip root or in /sdcard/Download, then run this again."

grep -q '<AndroidAttestation' "$KEYBOX_SRC" || die "The keybox has no AndroidAttestation root."
grep -q 'BEGIN CERTIFICATE' "$KEYBOX_SRC" || die "The keybox has no certificate."
grep -q 'PRIVATE KEY' "$KEYBOX_SRC" || die "The keybox has no private key."
if grep -q 'Software Attestation' "$KEYBOX_SRC"; then
  log "Warning: this keybox looks like a software AOSP key. It does not give Strong."
fi

if [ -x /data/adb/magisk/magisk ]; then
  MAGISK=/data/adb/magisk/magisk
elif command -v magisk >/dev/null 2>&1; then
  MAGISK=magisk
else
  die "Magisk was not found. This module is for Magisk only."
fi

log "Magisk: $MAGISK"
log "Keybox found. Its contents are not printed."

MODDIR=/data/adb/modules
UPDDIR=/data/adb/modules_update
TMP=/data/local/tmp/magiskstrong
mkdir -p "$TMP" /data/adb/tricky_store "$MODDIR" || die "Could not create the working directories."
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
    printf '%s' "pending removal"
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
    touch "$MODDIR/$id/disable"
    did=1
  fi
  if [ -d "$UPDDIR/$id" ] && [ ! -f "$UPDDIR/$id/disable" ]; then
    log "Disabling the pending install: $id"
    touch "$UPDDIR/$id/disable"
    did=1
  fi
  [ "$did" = 1 ] && NEED_REBOOT=1
  return 0
}

ksu_enable() {
  id="$1"
  changed=0
  for base in "$MODDIR" "$UPDDIR"; do
    [ -d "$base/$id" ] || continue
    if [ -f "$base/$id/remove" ] || [ -f "$base/$id/disable" ]; then
      rm -f "$base/$id/remove" "$base/$id/disable"
      log "Enabling: $id"
      changed=1
    fi
  done
  [ "$changed" = 1 ] && NEED_REBOOT=1
  return 0
}

is_conflict() {
  id="$1"
  name="$2"
  case "$id" in
    magiskstrong|playintegrityfix|tricky_store|zygisk-assistant|zygisksu|rezygisk|neozygisk)
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
    curl -fsSL -A magiskstrong -H "Accept: application/vnd.github+json" \
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
    curl -fL -A magiskstrong -o "$dest" "$url" || return 1
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
      log "Download failed. Using the local zip: $SCRIPT_DIR/$id.zip"
      cp -f "$SCRIPT_DIR/$id.zip" "$stage" || die "Could not copy $id.zip into the temporary directory."
    else
      die "Could not download $repo. Put the official zip next to the module as $id.zip. Page: https://github.com/$repo/releases/latest"
    fi
  fi
  "$MAGISK" --install-module "$stage" || die "Magisk could not install $id"
  module_present "$id" || die "After install, $id is missing from both $MODDIR and $UPDDIR"
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
[ "$found_any" = 1 ] || log "  no modules"

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
        log "Leaving LSPosed ($id) as it is. It can break Strong."
        ;;
    esac
  done
done

# Magisk already provides Zygisk. A second Zygisk stack blocks injection into Play Services.
if module_present zygisksu || module_present rezygisk || module_present neozygisk; then
  log "Disabling ZygiskNext, ReZygisk, and NeoZygisk. Magisk needs its built-in Zygisk."
  ksu_disable zygisksu
  ksu_disable rezygisk
  ksu_disable neozygisk
fi

zout=$("$MAGISK" --sqlite "SELECT value FROM settings WHERE key='zygisk';" 2>/dev/null || true)
case "$zout" in
  *1*)
    log "Zygisk is already on."
    ;;
  *)
    "$MAGISK" --sqlite "INSERT OR REPLACE INTO settings (key,value) VALUES ('zygisk',1);" >/dev/null 2>&1 || die "Could not turn Zygisk on."
    log "Zygisk is on. A reboot is required."
    NEED_REBOOT=1
    ;;
esac

dout=$("$MAGISK" --sqlite "SELECT value FROM settings WHERE key='denylist';" 2>/dev/null || true)
case "$dout" in
  *1*)
    "$MAGISK" --sqlite "INSERT OR REPLACE INTO settings (key,value) VALUES ('denylist',0);" >/dev/null 2>&1 || true
    "$MAGISK" --denylist disable >/dev/null 2>&1 || true
    log "Enforce DenyList is off. Otherwise Play Integrity Fork cannot inject into GMS."
    NEED_REBOOT=1
    ;;
  *)
    "$MAGISK" --denylist disable >/dev/null 2>&1 || true
    log "Enforce DenyList stays off."
    ;;
esac

deny_add() {
  pkg="$1"
  proc="$2"
  "$MAGISK" --denylist add "$pkg" "$proc" >/dev/null 2>&1 || true
  "$MAGISK" --sqlite "INSERT OR IGNORE INTO denylist (package_name,process) VALUES ('$pkg','$proc');" >/dev/null 2>&1 || true
}

log "Adding apps to the hide list. Enforce DenyList stays off."
deny_add com.android.vending com.android.vending
deny_add com.android.vending com.android.vending:background
deny_add com.google.android.gms com.google.android.gms
deny_add com.google.android.gms com.google.android.gms.persistent
deny_add com.google.android.gms com.google.android.gms.unstable
deny_add com.google.android.gms com.google.android.gms.ui
deny_add com.google.android.gms com.google.android.gms:snet
deny_add com.google.android.gms com.google.android.gms.identitycredentials
deny_add com.google.android.gsf com.google.android.gsf
deny_add com.google.android.gm com.google.android.gm
deny_add io.github.vvb2060.keyattestation io.github.vvb2060.keyattestation
deny_add gr.nikolasspyr.integritycheck gr.nikolasspyr.integritycheck
deny_add com.anu.developers3k.rootchecker com.anu.developers3k.rootchecker
deny_add com.kblack.demo_play_integrity_api com.kblack.demo_play_integrity_api
log "Do not grant root to com.google.android.gms."

PIF_DIR=$(active_dir playintegrityfix)
PIF_AUTHOR=""
if [ -n "$PIF_DIR" ]; then
  PIF_AUTHOR=$(prop_get "$PIF_DIR/module.prop" author)
fi
case "$PIF_AUTHOR" in
  *osm0sis*)
    log "Play Integrity Fork is already from osm0sis."
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
    log "playintegrityfix is from '$PIF_AUTHOR'. Reinstalling the osm0sis build."
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
  *) die "Play Integrity Fork is installed, but the author is not osm0sis (${PIF_AUTHOR:-empty}). The official osm0sis zip is required." ;;
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
log "Root hiding: $ZA_ID"

KEYBOX_DEST=/data/adb/tricky_store/keybox.xml
if [ "$KEYBOX_SRC" = "$KEYBOX_DEST" ]; then
  log "The keybox is already in /data/adb/tricky_store."
else
  log "Copying the keybox to /data/adb/tricky_store/keybox.xml"
  if [ -f "$KEYBOX_DEST" ]; then
    cp -f "$KEYBOX_DEST" /data/adb/tricky_store/keybox.xml.bak.module
    chmod 600 /data/adb/tricky_store/keybox.xml.bak.module 2>/dev/null || true
  fi
  umask 077
  cat "$KEYBOX_SRC" > "$KEYBOX_DEST" || die "Could not write the keybox."
  umask 022
fi
chmod 600 "$KEYBOX_DEST" || die "Could not set keybox permissions."
chown 0:0 "$KEYBOX_DEST" 2>/dev/null || true
chcon u:object_r:adb_data_file:s0 "$KEYBOX_DEST" 2>/dev/null || true
grep -q 'BEGIN CERTIFICATE' "$KEYBOX_DEST" || die "The written keybox cannot be read."
src_size=$(wc -c < "$KEYBOX_SRC" | tr -d ' \t\r\n')
dst_size=$(wc -c < "$KEYBOX_DEST" | tr -d ' \t\r\n')
[ "$src_size" = "$dst_size" ] || die "The written keybox size does not match the source."

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
  log "This canary is from 2026-10-07. Estimated expiry: 2026-11-18."
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
  log "autopif4 knows first_api_level per model. Fetching a fresh fingerprint."
  if sh "$AUTOPIF" --strong; then
    pull_pif_to_work || write_bluejay
  else
    log "autopif4 failed. Keeping the known Pixel 6a print."
    write_bluejay
  fi
else
  log "This Play Integrity Fork has no first_api_level table. Writing the known Pixel 6a print."
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
  log "$DEVICE_NAME with api_level ${API_NOW:-empty} does not pass Strong. Restoring Pixel 6a."
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
[ "$synced" = 1 ] || die "Nowhere to write custom.pif.prop: the playintegrityfix directory was not found."

printf '%s\n' "$COMPACT" > /data/adb/tricky_store/security_patch.txt
label_file /data/adb/tricky_store/security_patch.txt
log "security_patch.txt = $COMPACT"
log "tee_status was left unchanged."

if [ "$NEED_REBOOT" = 0 ] && [ -f "$MODDIR/playintegrityfix/killpi.sh" ]; then
  log "Restarting DroidGuard and the Play Store."
  # killpi.sh uses killall -v. Toybox on this phone treats -v as a signal name.
  sh "$MODDIR/playintegrityfix/killpi.sh" >/dev/null 2>&1 || true
  killall com.google.android.gms.unstable >/dev/null 2>&1 || true
  killall com.android.vending >/dev/null 2>&1 || true
fi

rm -f "$TMP/release.json" "$TMP"/*.zip "$WORK" 2>/dev/null || true

log "Done."
log "Keybox: /data/adb/tricky_store/keybox.xml"
log "Fingerprint: custom.pif.prop in the playintegrityfix module. spoofProvider=0."
log "Patch: /data/adb/tricky_store/security_patch.txt"
log "Zygisk is on. Enforce DenyList is off."
if [ "$NEED_REBOOT" = 1 ]; then
  if [ "$REBOOT" = 1 ]; then
    log "The required modules are in place. Rebooting."
    sync
    sleep 2
    reboot
  else
    log "A reboot is required, or the new modules will not run."
  fi
else
  log "Open Play Integrity API Checker and press CHECK."
  log "Expect BASIC, DEVICE, and STRONG."
fi
