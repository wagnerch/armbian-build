# Use the Ethernet MAC handed over by the vendor U-Boot (see emmc_autoscript and s905_autoscript):
# "mac=<mac>" at 0x1f00000. ethaddr is write-once in U-Boot and mainline already generated one from the chip
# serial, so import the string as the variable "mac" and force ethaddr from it. booti then writes it into the
# device tree as local-mac-address. Armbian's boot.cmd sources this file (fixup.scr) before booti.
if itest.l *0x1f00000 == 0x3d63616d; then if itest.b *0x1f00004 != 0; then env import -t 0x1f00000 21 mac; if test -n "${mac}"; then env set -f ethaddr "${mac}"; fi; fi; fi
