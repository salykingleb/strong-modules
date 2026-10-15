# Strong Play Integrity

Two modules for the same result: BASIC, DEVICE, and STRONG.

| File | Installation Target |
| --- | --- |
| [magisk-strong.zip](magisk-strong.zip) | Magisk 20.4 and newer, including Magisk Alpha |
| [ksu-strong.zip](ksu-strong.zip) | KernelSU, via the KernelSU app only |

The source code is located in the `magisk/` and `kernelsu/` folders. The module texts are in English.

Both modules install or enable:

* [Play Integrity Fork](https://github.com/osm0sis/PlayIntegrityFork) by osm0sis
* [Tricky Store](https://github.com/5ec1cff/TrickyStore)
* [Zygisk Assistant](https://github.com/snake-4/Zygisk-Assistant)

Conflicting modules are disabled but not removed.

`spoofProvider` remains set to 0. Otherwise, the attestation will bypass the keybox.

## Magisk

Requires [Magisk](https://github.com/topjohnwu/Magisk) version 20.4 or newer. Uses the built-in Zygisk. ZygiskNext, ReZygisk, and NeoZygisk (if installed) are disabled.

1. Download `magisk-strong.zip`.
2. Open Magisk, go to the "Modules" tab, and select "Install from storage".
3. Choose `magisk-strong.zip`.
4. Tap "Action".
5. If the module installs new packages, reboot the phone if it doesn't restart automatically. If Play Integrity Fork, Tricky Store, and Zygisk Assistant were already installed, a reboot is not required.

What the installation does:

* Enables Zygisk;
* Keeps Enforce DenyList disabled (otherwise, Play Integrity Fork won't inject into GMS);
* Adds Play Store, GMS, GSF, Gmail, Key Attestation, Play Integrity API Checker, and Advanced Root Checker to the hiding list.

## KernelSU

Requires [KernelSU](https://github.com/tiann/KernelSU). This archive cannot be flashed via recovery. Do not install the module on a phone with Magisk and without `ksud`: the script will stop and make no changes.

KernelSU doesn't have built-in Zygisk, so the module installs [ZygiskNext](https://github.com/Dr-TSNG/ZygiskNext). ReZygisk and NeoZygisk are disabled.

1. Download `ksu-strong.zip`.
2. Open the KernelSU app, go to the modules tab, tap the "+" button, and select the archive.
3. Wait for the installation to finish, then reboot the phone.
4. After rebooting, the Strong Play Integrity module will show an "Action" button. Next to it, there's a module page with a "Start" button. Both trigger the same setup.

The "Action" button isn't available before reboot. A fresh installation is stored in `/data/adb/modules_update/ksustrong`, while the app only reads `/data/adb/modules`. Rebooting moves `action.sh` and the `webroot` page there.

Root hiding on KernelSU is handled by Zygisk Assistant together with Umount modules for the required app. Enforce DenyList in ZygiskNext remains disabled.

## Author: https://t.me/Premium_SMS_Messenger

**If this work was useful to you, you can support the developer with USDT (TRC-20):**

```
THSLZyomC5h7kmQSNPqBSCR6eD1YTD1RXr
```
