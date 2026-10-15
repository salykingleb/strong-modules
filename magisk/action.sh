#!/system/bin/sh
# Magisk runs this file when the Action button is pressed.
# The app shows stdout only, so send stderr there too.
MODDIR=${0%/*}
exec 2>&1
exec sh "$MODDIR/setup.sh"
