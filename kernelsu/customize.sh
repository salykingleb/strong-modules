#!/system/bin/sh
# Sourced by the KernelSU installer after the zip is extracted.

ui_print " "
ui_print "Strong Play Integrity"
ui_print "Put your own keybox.xml in this zip, or in /sdcard/Download/keybox.xml."
ui_print "The module does not download a keybox."
ui_print "Running setup..."

if sh "$MODPATH/setup.sh" --no-reboot; then
  ui_print "Setup finished."
  ui_print "Reboot. If a module was still missing, open this module and tap Action."
else
  ui_print "Setup did not finish."
  ui_print "Add keybox.xml, reboot, then tap Action or press Start."
fi

touch "$MODPATH/skip_mount"
chmod 755 "$MODPATH/action.sh" "$MODPATH/setup.sh" 2>/dev/null || true
