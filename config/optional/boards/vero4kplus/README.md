# OSMC Vero 4K+ (Amlogic S905D) on Armbian

The Vero 4K+ is an Amlogic S905D (GXL) set-top box with 2GB RAM and 16GB eMMC. The mainline kernel supports it
(`meson-gxl-s905d-vero4k-plus.dts`); this board config adds the bootloader side.

## How it boots (and why)

The eMMC carries OSMC's bootloader chain (BL2, BL30/BL301, BL31, BL32 and a vendor U-Boot). Replacing it did not work:
every chain we built ourselves (open BL2 with plain blobs, the shipped reference sets, the vendor BL2 with a plain BL33)
loaded over USB but never handed over to a bootloader, and the vendor blobs each carry a 512-byte signature-like block
that we cannot reproduce. We believe the vendor BL2 only accepts signed images; this is the best explanation we have,
not something we proved. So, like `aml-c400-plus`, this board **chainloads a mainline U-Boot** (bare BL33) from the
vendor U-Boot:

```
ROM -> vendor BL2/BL3x -> vendor U-Boot -> s905_autoscript (SD/USB) or emmc_autoscript (eMMC)
    -> /boot/u-boot.ext (mainline U-Boot v2026.10) -> boot.scr -> kernel
```

- The vendor U-Boot's saved environment must contain `bootcmd=run start_autoscript; run storeboot` and a
  `start_emmc_autoscript` that loads `emmc_autoscript` from `mmc 1`. `aml_autoscript` writes that environment.
- `u-boot.ext` is built by Armbian from `patch/u-boot/v2026.10/board_vero4kplus` (a `vero4kplus_defconfig` and a
  `-u-boot.dtsi`). It must stay under 1MiB (vendor BL2 limit); the board config fails the build if it grows.
- Escape hatch: a non-empty file named `chain.off` on the boot partition or on a USB stick skips the chainload and
  boots the legacy way (`uImage`/`uInitrd` straight from the vendor U-Boot).

## Installing

**SD card / USB, first time on a stock OSMC unit.** A stock environment only boots a `kernel.img` from the SD card
(`osmcfromsd`, OSMC's own installer), so it ignores an Armbian card. The toothpick button (the `upgrade_key`, `GPIOAO_2`)
sends the vendor U-Boot into its `update` path, which loads `aml_autoscript` from the card's FAT partition (or a USB
drive) and runs it:

1. Write the Armbian image to an SD card or USB drive and insert it. Do not connect a USB cable to the OTG port: the
   update path waits for a USB host there first.
2. Hold the toothpick button while applying power, and keep holding it for at least three seconds.
3. `aml_autoscript` resets the vendor U-Boot environment (`defenv`), stores `bootcmd=run start_autoscript; run
   storeboot` plus a `start_autoscript` that looks for `s905_autoscript` on the SD card, then USB, then
   `emmc_autoscript` on the eMMC, and reboots.

From then on the card boots without the button. `defenv` discards the stock environment, so if you may want OSMC back,
save it first (`fw_printenv` on OSMC). This sequence is derived from the stock environment variables; it has not been
run on a factory-fresh unit (ours had already been through it).

**eMMC:** boot Armbian from SD/USB, then run:

```
sudo vero4kplus-install-emmc --backup-dir /root/emmc-backup      # add --dry-run first to see the plan
```

This replaces OSMC. It keeps the vendor bootloader (first 4MiB), the MPT partition table (36MiB), the saved
environment (628MiB) and the small vendor partitions, and it only writes bytes 446-511 of sector 0 (the DOS table).
It creates `p1` FAT32 `/boot` (512MiB, the old `instaboot` area at 836MiB) and `p2` ext4 root (1396MiB to the end),
and wipes OSMC's LVM volume group (`vero-nand`, one logical volume spanning the `cache`, `instaboot`, `system` and
`data` partitions). The MPT is not rewritten, so it still describes the old layout; nothing in the normal boot path
reads those entries. The installer refuses to run unless the board is a Vero 4K+, the target is an eMMC that is not
the running system and is unmounted, the stock OSMC layout and a CRC-valid vendor environment are present, and it
asks you to type the device name. It takes a verified backup of the first 836MiB first, copies the running system with
`rsync`, and checks that every preserved region is byte-identical afterwards. Then power off, **remove the SD card**
and power on. (The generic `armbian-install` is not used: it wipes the whole disk, which would erase the vendor
bootloader.)

## After installing the image (manual steps)

The image boots without these, but Bluetooth does not work until you install its firmware.
On a stock OSMC unit, do the one-time vendor setup first (see "Installing").

1. **First boot.** Armbian's first-login wizard asks for a root password and a user, and the root filesystem grows to
   fill the SD card or eMMC.

2. **Ethernet MAC: nothing to do.** The unit's real MAC address is kept in the vendor U-Boot's secure storage. The
   vendor autoscript reads it (`keyman read mac`) and leaves it in RAM for the chainloaded mainline U-Boot, and
   `/boot/fixup.scr` (sourced by Armbian's `boot.cmd` before `booti`) sets `ethaddr` from it, so Linux gets the MAC
   printed on the label. Without this, mainline U-Boot would use its own address, which is stable but derived from the
   chip serial (for example `be:9b:54:61:46:2d`) and differs from the label. Check with
   `cat /sys/class/net/end0/address`. This was tested on one unit, on the eMMC boot path. If the address is wrong, pin
   it by hand:

   ```
   sudo tee /etc/systemd/network/10-end0.link <<'EOF'
   [Match]
   OriginalName=end0

   [Link]
   MACAddress=xx:xx:xx:xx:xx:xx
   EOF
   sudo update-initramfs -u && sudo reboot
   ```

   The `.link` file is copied into the initramfs, so run `update-initramfs -u` both after adding it and after removing
   it. The Wi-Fi and Bluetooth addresses come from the chip and are stable (Bluetooth is the Wi-Fi address plus one).

3. **Bluetooth.** Install the controller firmware as described under "Bluetooth firmware (not included)" and
   `sudo apt install bluez`, then reboot. `dmesg | grep hci0` should show `... .hcd' Patch`, and `bluetoothctl show`
   should list the controller. The kernel side was verified; BlueZ itself was not installed during our tests.

4. **Wi-Fi.** The built-in AP6255 (`wlan0`) works with the stock firmware. Connect with
   `sudo nmcli device wifi connect "SSID" password "PASSWORD" ifname wlan0`. Scanning was verified; connecting was not.

## Recovery

- **eMMC does not boot:** insert the SD card (tried first by the vendor U-Boot), or put a USB stick with a non-empty
  `chain.off` file in to boot the legacy path. Restore the installer's backup with
  `dd if=emmc-first-836MiB.img of=/dev/mmcblkX bs=1M conv=fsync` (X = the eMMC).
- **Bootloader erased or broken:** the ROM drops into USB burn mode (`1b8e:c003`) when the eMMC has no valid
  bootloader, or when an Amlogic HDMI boot dongle programmed `boot@USB` is attached
  (<https://github.com/superna9999/linux/wiki/Amlogic-HDMI-Boot-Dongle>). With a dongle programmed `boot@SDC`, the
  ROM boots the vendor bootloader from an SD card written as: bytes 0-10 and sectors 1 onward of OSMC's
  `/opt/vero3/uboot-vero4kplus.bin` (`dd bs=1 count=11`, then `dd bs=512 skip=1 seek=1`). Without the dongle the ROM does
  not boot from SD on this board. From a booted system you can restore the eMMC bootloader the same way.
- Back up the eMMC before experimenting. A stock OSMC can be reinstalled from OSMC's installer image, but the backup is the
  only copy of this unit's own bootloader (which differs from the file OSMC publishes), its saved environment, and its
  OSMC settings and data.

## Bluetooth firmware (not included)

The AP6255 Bluetooth controller (`BCM4345C0`, Ampak) needs OSMC's patch file to work as it does on OSMC. The kernel asks
for `brcm/BCM4345C0.osmc,vero4k-plus.hcd`. That file is not in `linux-firmware` and not in Armbian's firmware repository
(checked November 2026; Armbian only carries a generic `BCM4345C0.hcd`, a different file), so images do not contain it. It
is published in OSMC's source repository, and it is the same file as `/etc/firmware/BCM4345C0.hcd` in OSMC's
`vero3-wifi-osmc` package. Its redistribution terms are not stated there, so we do not ship it; install it yourself:

```
sudo curl -fL -o '/lib/firmware/brcm/BCM4345C0.osmc,vero4k-plus.hcd' \
  https://raw.githubusercontent.com/osmc/osmc/master/package/vero3-wifi-osmc/files/etc/firmware/BCM4345C0.hcd
echo '977763e0e9efe9555fa009c2a2027ba46ad9fec749de01f0c677d2e2157eb90f  /lib/firmware/brcm/BCM4345C0.osmc,vero4k-plus.hcd' | sudo sha256sum -c
```

Reboot afterwards; the kernel loads the file when the controller initialises (`dmesg | grep hci0` shows
`... .hcd' Patch`). BlueZ (`bluez`) is not part of the minimal image either.

## Verified on hardware (kernel 7.3.x edge, trixie)

HDMI (1080p framebuffer), Mali-450 GPU (`lima`), Ethernet at gigabit (940 Mbit/s with iperf3; the MAC is handed over from the vendor
U-Boot, see above), both USB 2.0 host ports (the white OTG port is peripheral-only in the device tree), Wi-Fi scanning
(AP6255), the Bluetooth controller with OSMC's patch firmware, the IR receiver (it decodes NEC, but the kernel's NEC
decoder is off by default and there is no keymap), clock synchronisation (chrony; the RTC is virtual, so the clock
starts from the time saved at shutdown). A USB keyboard was tested earlier by the maintainer.

Not verified: audible audio. HDMI audio needs a display that supports it. The analog output was silent with a 3-pole
plug in the AV jack, although the amplifier enable GPIO matches OSMC's firmware and switches on during playback; it needs
a 4-pole AV cable to settle. HDMI-CEC and hardware video decoding were not tested.

## Package contents

- `config/boards/vero4kplus.csc`: board config, U-Boot pin and packaging, hooks.
- `patch/u-boot/v2026.10/board_vero4kplus/`: the U-Boot defconfig patch.
- `_packages/bsp-cli/usr/share/armbian/{aml,s905,emmc}_autoscript.cmd`: vendor U-Boot scripts (installed to `/boot`).
- `_packages/bsp-cli/usr/share/armbian/fixup.cmd`: mainline U-Boot script (installed as `/boot/fixup.scr`) that sets the
  Ethernet MAC handed over by the vendor U-Boot.
- `_packages/bsp-cli/etc/kernel/postinst.d/99-uboot`: builds `uImage`, refreshes `/boot/u-boot.ext` from the
  `linux-u-boot` package.
- `_packages/bsp-cli/usr/sbin/vero4kplus-install-emmc`: the eMMC installer.
