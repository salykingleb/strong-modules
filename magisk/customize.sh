#!/system/bin/sh
# Sourced by the Magisk installer after the zip is extracted.
# Do not exit: this file is sourced by the installer.

ui_print " "
ui_print "Strong Play Integrity for Magisk"
ui_print "Put your own keybox.xml or Keybox.xml in the zip root"
ui_print "or in /sdcard/Download."
ui_print "This module does not download a keybox."
ui_print "Running setup..."

if sh "$MODPATH/setup.sh" --no-reboot; then
  ui_print "Setup finished."
  ui_print "Reboot the phone if a new module was installed. Press Action to run setup again."
else
  ui_print "Setup stopped."
  ui_print "Add a keybox, reboot, and press Action."
fi

touch "$MODPATH/skip_mount"
chmod 755 "$MODPATH/action.sh" "$MODPATH/setup.sh" 2>/dev/null || true

# A live install keeps the real files in modules_update until reboot and
# copies only module.prop into /data/adb/modules. Magisk shows the Action
# button only when action.sh is in that live directory.
MODID=$(awk 'index($0, "id=") == 1 { print substr($0, 4); exit }' "$MODPATH/module.prop")
LIVE=/data/adb/modules/$MODID
if [ -n "$MODID" ] && [ "$MODPATH" != "$LIVE" ]; then
  mkdir -p "$LIVE"
  cp -f "$MODPATH/action.sh" "$LIVE/action.sh"
  cp -f "$MODPATH/setup.sh" "$LIVE/setup.sh"
  cp -f "$MODPATH/module.prop" "$LIVE/module.prop"
  cp -f "$MODPATH/skip_mount" "$LIVE/skip_mount"
  chmod 755 "$LIVE/action.sh" "$LIVE/setup.sh"
  chmod 644 "$LIVE/module.prop" "$LIVE/skip_mount" 2>/dev/null || true
  ui_print "Action button files are in the live module directory."
fi
