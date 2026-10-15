#!/system/bin/sh
# KernelSU runs this when the user taps the Action button.
MODDIR=${0%/*}
exec sh "$MODDIR/setup.sh"
