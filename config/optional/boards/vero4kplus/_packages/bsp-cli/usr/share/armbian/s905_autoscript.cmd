# Chainload the mainline U-Boot (/boot/u-boot.ext) instead of booting from the vendor U-Boot.
# Escape hatch: a non-empty file named chain.off on the boot partition or on a USB stick skips the
# chainload. If u-boot.ext is missing or unreadable, the legacy boot below is used instead.
setenv chain_addr 0x1000000
setenv chain_ok 1
usb start
if fatload usb 0 ${chain_addr} chain.off; then setenv chain_ok 0; fi
if fatload mmc 0 ${chain_addr} chain.off; then setenv chain_ok 0; fi
# Hand the Ethernet MAC from the vendor secure storage to the chainloaded mainline U-Boot.
# Mailbox at 0x1f00000: the text "mac=" followed by the MAC string that keyman returns; fixup.scr uses it.
mw.b 1f00000 6d; mw.b 1f00001 61; mw.b 1f00002 63; mw.b 1f00003 3d
mw.b 1f00004 0 20
if keyman init 0x1234; then keyman read mac 1f00004 str; fi
if test ${chain_ok} = 1; then if fatload mmc 0 ${chain_addr} u-boot.ext; then echo Chainloading u-boot.ext; icache off; dcache off; go ${chain_addr}; fi; for chain_usb in 0 1 2 3; do if fatload usb ${chain_usb} ${chain_addr} u-boot.ext; then echo Chainloading u-boot.ext; icache off; dcache off; go ${chain_addr}; fi; done; fi
# Legacy boot (vendor U-Boot boots the kernel directly)
setenv env_addr 0x1040000
setenv initrd_loadaddr 0x13000000
setenv boot_start 'bootm ${loadaddr} ${initrd_loadaddr} ${dtb_mem_addr}'
setenv try_boot_start 'if fatload ${devtype} ${devnum} ${loadaddr} uImage; then fatload ${devtype} ${devnum} ${env_addr} armbianEnv.txt && env import -t ${env_addr} ${filesize} && setenv bootargs "root=${rootdev} rootwait rootfstype=ext4 console=ttyS0,115200 console=tty1 consoleblank=0 coherent_pool=2M loglevel=1 libata.force=noncq" && fatload ${devtype} ${devnum} ${dtb_mem_addr} dtb/${fdtfile} && fatload ${devtype} ${devnum} ${initrd_loadaddr} uInitrd && run boot_start; fi'
setenv devtype mmc
setenv devnum 0
run try_boot_start
setenv devtype usb
for devnum in 0 1 2 3 ; do run try_boot_start ; done
