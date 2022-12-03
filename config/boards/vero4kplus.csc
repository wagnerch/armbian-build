# OSMC Vero 4K+ (Amlogic S905D, 2GB RAM, 16GB eMMC)
#
# The vendor (OSMC) bootloader in the eMMC cannot be replaced: its BL2/BL30/BL31 blobs are signed
# and only accept the vendor BL33. So, like the aml-c400-plus, we chainload a mainline U-Boot (bare BL33):
#
#   ROM -> vendor BL2/BL3x -> vendor U-Boot -> (emmc|s905)_autoscript -> u-boot.ext (mainline) -> boot.scr -> kernel
#
# - /boot/s905_autoscript is read by the vendor U-Boot from SD/USB, /boot/emmc_autoscript from the eMMC (mmc 1).
# - /boot/u-boot.ext is the mainline U-Boot (bare BL33), refreshed from the linux-u-boot package.
# - Escape hatch: a file named chain.off on the boot partition or a USB stick skips the chainload
#   and boots the legacy way (uImage/uInitrd) straight from the vendor U-Boot.
BOARD_NAME="vero4kplus"
BOARD_VENDOR="osmc"
BOARDFAMILY="meson-gxl"
BOOTSIZE="512"
BOOTFS_TYPE="fat"
KERNEL_TARGET="current,edge"
SERIALCON="ttyAML0"
FULL_DESKTOP="yes"
ASOUND_STATE="asound.state.mesongx"
BOOT_LOGO="no"
EXTRAWIFI="no"
SKIP_BOOTSPLASH="yes"
BOOT_FDT_FILE="amlogic/meson-gxl-s905d-vero4k-plus.dtb"
SRC_CMDLINE='rootflags=data=writeback console=ttyAML0,115200n8 console=tty0'

# Mainline U-Boot, built as a bare BL33. The board defconfig comes from patch/u-boot/v2026.10/board_vero4kplus.
BOOTCONFIG="vero4kplus_defconfig"
BOOTBRANCH_BOARD="tag:v2026.10"
BOOTPATCHDIR="v2026.10"

# 'u-boot.bin' is the bare BL33 here (no FIP repacking), shipped in the u-boot package as 'u-boot.ext'.
declare -g UBOOT_TARGET_MAP="u-boot.bin;;u-boot.bin:u-boot.ext"

# The ROM never loads a bootloader from the SD card gap, so don't write one there.
function post_family_config__vero4kplus_no_uboot_in_image() {
	unset write_uboot_platform
	function write_uboot_platform() {
		return 0
	}
}

# The vendor BL2 limits BL33 to 1MiB (loaded between 0x01000000 and 0x01100000); refuse a bigger u-boot.
function post_uboot_custom_postprocess__vero4kplus_check_bl33_size() {
	declare -i bl33_size
	bl33_size=$(stat -c %s u-boot.bin)
	display_alert "u-boot for ${BOARD}/${BRANCH}" "bl33 size: ${bl33_size} bytes" "info"
	if [ "${bl33_size}" -gt 1048576 ]; then
		display_alert "u-boot for ${BOARD}/${BRANCH}" "bl33 size exceeds 1MiB, chainloading would fail! (${bl33_size} bytes)" "error"
		return 1
	fi
	return 0
}

# Put the chainload target on the (FAT) boot partition of the image.
function pre_umount_final_image__export_uboot_ext_vero4kplus() {
	: "${version:?version is not set}"
	local uboot_name="linux-u-boot-${BRANCH}-${BOARD}"
	display_alert "Exporting u-boot.ext" "${uboot_name} (bare bl33 for chainloading)" "info"
	run_host_command_logged cp -pv "${MOUNT}/usr/lib/${uboot_name}/u-boot.ext" "${MOUNT}/boot/u-boot.ext"
}

function post_family_tweaks__config_vero4kplus_bsp() {
	display_alert "$BOARD" "Installing bsp files" "info"

	chroot_sdcard /etc/kernel/postinst.d/99-uboot
}

function post_family_tweaks_bsp__config_vero4kplus_bsp_preinst() {
	: "${destination:?destination is not set}"
	run_host_command_logged chmod -v 755 "${destination}"/usr/sbin/vero4kplus-install-emmc

	display_alert "${BOARD}" "Adding bsp-cli preinst logic" "info"
	# The boot filesystem is FAT: dpkg cannot hard-link the existing files as backup, so remove them first.
	function vero4kplus_bsp_cli_preinst() {
		# NOTE: Armbian pastes this body inline into the package script, so no "return" here.
		for f in aml_autoscript emmc_autoscript s905_autoscript; do
			[ -f /boot/${f} ] && rm -f /boot/${f}
		done
	}
	preinst_functions+=('vero4kplus_bsp_cli_preinst')
	if false; then vero4kplus_bsp_cli_preinst; fi # so shellcheck does not complain the function is unused
}

function post_family_tweaks_bsp__config_vero4kplus_bsp_postinst() {
	postinst_functions+=("board_side_vero4kplus_bsp_cli_postinst_hook")
	function board_side_vero4kplus_bsp_cli_postinst_hook() {
		# Never touch /boot/u-boot.ext here (it is refreshed by /etc/kernel/postinst.d/99-uboot).
		for f in aml_autoscript emmc_autoscript s905_autoscript; do
			[ -f /usr/share/armbian/${f}.cmd ] && cp -p /usr/share/armbian/${f}.cmd /boot/ && mkimage -C none -A arm -T script -d /boot/${f}.cmd /boot/${f} > /dev/null 2>&1
		done
		# fixup.scr is sourced by boot.cmd under mainline U-Boot (hands over the MAC from the vendor U-Boot)
		[ -f /usr/share/armbian/fixup.cmd ] && cp -p /usr/share/armbian/fixup.cmd /boot/ && mkimage -C none -A arm -T script -d /boot/fixup.cmd /boot/fixup.scr > /dev/null 2>&1
	}
}
