setenv env_addr 0x1040000
setenv initrd_loadaddr 0x13000000
setenv boot_start 'bootm ${loadaddr} ${initrd_loadaddr} ${dtb_mem_addr}'
setenv try_boot_start 'if fatload ${devtype} ${devnum} ${loadaddr} uImage; then fatload ${devtype} ${devnum} ${env_addr} armbianEnv.txt && env import -t ${env_addr} ${filesize} && setenv bootargs "root=${rootdev} rootwait rootfstype=ext4 console=ttyS0,115200 console=tty1 consoleblank=0 coherent_pool=2M loglevel=1 libata.force=noncq" && fatload ${devtype} ${devnum} ${dtb_mem_addr} dtb/${fdtfile} && fatload ${devtype} ${devnum} ${initrd_loadaddr} uInitrd && run boot_start; fi'
setenv devtype mmc
setenv devnum 0
run try_boot_start
setenv devtype usb
for devnum in 0 1 2 3 ; do run try_boot_start ; done
