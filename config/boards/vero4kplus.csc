# Amlogic S9xx based TVBox
BOARD_NAME="vero4kplus"
BOARDFAMILY="meson-gxl"
BOOTCONFIG="none"
BOOT_FDT_FILE="amlogic/meson-gxl-s905d-vero4k-plus.dtb"
BOOTSIZE="512"
BOOTFS_TYPE="fat"
KERNEL_TARGET="current,edge"
SERIALCON="ttyAML0"
FULL_DESKTOP="yes"
ASOUND_STATE="asound.state.mesongx"
BOOT_LOGO="no"
EXTRAWIFI="no"
SKIP_BOOTSPLASH="yes"
SRC_CMDLINE='rootflags=data=writeback console=ttyAML0,115200n8 console=tty0'

function post_family_tweaks__config_vero4kplus_bsp() {
   display_alert "$BOARD" "Installing bsp files" "info"

   chroot_sdcard /etc/kernel/postinst.d/99-uboot
}

function post_family_tweaks_bsp__config_vero4kplus_bsp_postinst() {
   postinst_functions+=("board_side_vero4kplus_bsp_cli_postinst_hook")
   function board_side_vero4kplus_bsp_cli_postinst_hook() {
      for f in aml_autoscript s905_autoscript
      do
         [ -f /usr/share/armbian/${f}.cmd ] && cp -p /usr/share/armbian/${f}.cmd /boot/ && mkimage -C none -A arm -T script -d /boot/${f}.cmd /boot/${f} > /dev/null 2>&1
      done
   }
}
