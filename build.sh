#!/bin/bash

# --- TODO
# * DONE remove dependance on debian based host
# ** DONE use linaro toolchain
#     https://launchpad.net/linaro-toolchain-binaries/trunk/
# * DOING clean up script
# * TODO package the kernel in a real slackware package
# * TODO switch userland to hard-float binaries
# * TODO build rootfs from slackwarearm-current
#    ftp://ftp.arm.slackware.com/slackwarearm/slackwarearm-devtools/minirootfs/scripts/

if [ ! -x /usr/bin/mkimage ]; then
    echo "Missing u-boot tools"
    echo "Please install them from http://www.slackware.com/~alien/slackbuilds/u-boot-tools/"
    exit 1
fi

# --- Configuration -------------------------------------------------------------
#change to your needs
VERSION="SlackwareARM_0.1"
DEST_LANG="en_US"
DEST_LANGUAGE="us"
COMPILE="true"
DEST=/home/cycojesus/cubieslack
DISPLAY=3  # "3:hdmi; 4:vga"
IMAGE_SIZE_MB=2000
SLACKWARE_VERSION=14.1
ROOTFS_VERSION=04Nov13
CONFIG_HZ=300HZ  # 250HZ, 300HZ or 1000HZ
# --- End -----------------------------------------------------------------------

SRC=$(pwd)
CWD=$(pwd)
set -e

mkdir -p $DEST

#Requires root ..
if [ "$UID" -ne 0 ]
then echo "Please run as root"
     exitssid=CUBIE
     interface=wlan0
     hw_mode=g
     channel=1
     bridge=br0

     logger_syslog=0
     logger_syslog_level=0

     wmm_enabled=0
     wpa=2
     preamble=1
     wpa_psk=66eb31d2b48d19ba216f2e50c6831ee11be98e2fa3a8075e30b866f4a5ccda27
     wpa_passphrase=12345678
     wpa_key_mgmt=WPA-PSK
     wpa_pairwise=TKIP
     rsn_pairwise=CCMP
     auth_algs=1
     macaddr_acl=0
fi

echo "Building Cubietruck-Slackware in $DEST from $SRC"
sleep 3

#--------------------------------------------------------------------------------
# Downloading necessary files for building - aka Toolchain
#--------------------------------------------------------------------------------
echo "------ Downloading cross-compiler"
#Read this for further information if you run into problems with gcc compiler
#http://linux-sunxi.org/Toolchain

wget -c https://launchpadlibrarian.net/155358238/gcc-linaro-arm-linux-gnueabihf-4.8-2013.10_linux.tar.xz
tar xf gcc-linaro-arm-linux-gnueabihf-4.8-2013.10_linux.tar.xz

CROSS_COMPILE=$PWD/gcc-linaro-arm-linux-gnueabihf-4.8-2013.10_linux/bin/arm-linux-gnueabihf-

#--------------------------------------------------------------------------------
# Preparing output / destination files
#--------------------------------------------------------------------------------
echo "------ Fetching files from github"
mkdir -p $DEST/output
cp output/uEnv.txt $DEST/output

# # u-boot tools
# if [ -d "$DEST/u-boot" ]; then
#     (cd $DEST/u-boot;
#      git pull)
# else
#     git clone git://git.denx.de/u-boot.git $DEST/u-boot
# fi

# Boot loader
if [ -d "$DEST/u-boot-sunxi" ]
then
    cd $DEST/u-boot-sunxi ; git pull; cd $SRC
else
    git clone https://github.com/cubieboard/u-boot-sunxi $DEST/u-boot-sunxi
    # Applying Patch for 2gb memory
    patch -f $DEST/u-boot-sunxi/include/configs/sunxi-common.h < $SRC/patch/memory.patch || true
fi

# Allwinner tools
if [ -d "$DEST/sunxi-tools" ]
then
    cd $DEST/sunxi-tools; git pull; cd $SRC
else
    git clone https://github.com/linux-sunxi/sunxi-tools.git $DEST/sunxi-tools
fi

# Hardware configurations
if [ -d "$DEST/cubie_configs" ]
then
    cd $DEST/cubie_configs; git pull; cd $SRC
else
    git clone https://github.com/cubieboard/cubie_configs $DEST/cubie_configs

    # Applying Patch for high load. Could cause troubles with USB OTG port
    sed -e 's/usb_detect_type     = 1/usb_detect_type     = 0/g' $DEST/cubie_configs/sysconfig/linux/cubietruck.fex > $DEST/cubie_configs/sysconfig/linux/ct.fex

    # Prepare fex files for VGA & HDMI
    sed -e 's/screen0_output_type.*/screen0_output_type     = 3/g' $DEST/cubie_configs/sysconfig/linux/ct.fex > $DEST/cubie_configs/sysconfig/linux/ct-hdmi.fex
    sed -e 's/screen0_output_type.*/screen0_output_type     = 4/g' $DEST/cubie_configs/sysconfig/linux/ct.fex > $DEST/cubie_configs/sysconfig/linux/ct-vga.fex
fi

# Patwood's kernel 3.4.75+
if [ -d "$DEST/linux-sunxi" ]
then
    cd $DEST/linux-sunxi; git pull -f; cd $SRC
else
    git clone https://github.com/patrickhwood/linux-sunxi $DEST/linux-sunxi

    ###PATCH kernel CONFIG_HZ, Arm dfault is hardcoded 100hz (10ms latency!). For mulitimedia and desktop a higher frequency is recomended.
    test -f $SRC/patch/$CONFIG_HZ.patch && patch -f $DEST/linux-sunxi/arch/arm/Kconfig < $SRC/patch/$CONFIG_HZ.patch
fi

#--------------------------------------------------------------------------------
# Compiling everything
#--------------------------------------------------------------------------------
echo "------ Compiling kernel boot loaderb"

# Copying Kernel config
cp $SRC/config/kernel.config $DEST/linux-sunxi/

# echo "------ Compiling mkimage"
# cd $DEST/u-boot
# touch include/autoconf.mk
# touch include/autoconf.mk.dep
# mkdir include/generated
# touch include/generated/generic-asm-offsets.h
# touch lib/asm-offsets.s
# touch {arch/arm/cpu/arm926ejs,examples/standalone,tools,tools/env}/.depend
# make tools HOSTCC="gcc $SLKCFLAGS" HOSTSTRIP=/bin/true CROSS_COMPILE=""
# export PATH=$PATH:$(pwd)/tools/

echo "------ Compiling boot loader"
cd $DEST/u-boot-sunxi
make clean && make -j2 'cubietruck' CROSS_COMPILE=$CROSS_COMPILE

echo "------ Compiling sunxi tools"
cd $DEST/sunxi-tools
make clean && make fex2bin && make bin2fex
mkdir -p $CWD/bin/
cp fex2bin bin2fex $CWD/bin/
# hardware configuration
$CWD/bin/fex2bin $DEST/cubie_configs/sysconfig/linux/ct-vga.fex $DEST/output/script-vga.bin
$CWD/bin/fex2bin $DEST/cubie_configs/sysconfig/linux/ct-hdmi.fex $DEST/output/script-hdmi.bin

echo "------ Compiling kernel"
if [ "$COMPILE" = "true" ]; then
    # kernel image
    echo "------ Compiling kernel"
    cd $DEST/linux-sunxi
    make clean

    # Adding wlan firmware to kernel source
    cd $DEST/linux-sunxi/firmware;
    unzip -o $SRC/bin/ap6210.zip
    cd $DEST/linux-sunxi

    make -j2 ARCH=arm CROSS_COMPILE=$CROSS_COMPILE sun7i_defconfig

    # get proven config
    cp $DEST/linux-sunxi/kernel.config $DEST/linux-sunxi/.config
    make -j2 ARCH=arm CROSS_COMPILE=$CROSS_COMPILE uImage modules
    make -j2 ARCH=arm CROSS_COMPILE=$CROSS_COMPILE INSTALL_MOD_PATH=output modules_install
    make -j2 ARCH=arm CROSS_COMPILE=$CROSS_COMPILE INSTALL_HDR_PATH=output headers_install
fi

#--------------------------------------------------------------------------------
# Creating SD Images
#--------------------------------------------------------------------------------
echo "------ Creating SD Images"
cd $DEST/output
# create 2Gb image and mount image to next free loop device
dd if=/dev/zero of=slackware_rootfs.raw bs=1M count=$IMAGE_SIZE_MB
LOOP0=$(losetup -f)
losetup $LOOP0 slackware_rootfs.raw

echo "------ Partitionning and mounting filesystem"
# make image bootable
dd if=$DEST/u-boot-sunxi/u-boot-sunxi-with-spl.bin of=$LOOP0 bs=1024 seek=8

# create one partition starting at 2048 which is default
(echo n; echo p; echo 1; echo; echo; echo w) | fdisk $LOOP0 >> /dev/null || true

# just to make sure
partprobe $LOOP0

LOOP1=$(losetup -f)
# 2048 (start) x 512 (block size) = where to mount partition
losetup -o 1048576 $LOOP1 $LOOP0

# create filesystem
mkfs.ext4 $LOOP1

# create mount point and mount image
mkdir -p $DEST/output/sdcard/
mount $LOOP1 $DEST/output/sdcard/

echo "------ Get basic Slackware System"
cd $DEST/output/sdcard/
wget -c ftp://ftp.arm.slackware.com/slackwarearm/slackwarearm-devtools/minirootfs/roots/slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz
tar xf slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz
sync
rm slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz

cat > $DEST/output/sdcard/etc/motd <<EOF
	      _      _        _                       _
  ___  _   _ | |__  (_)  ___ | |_  _ __  _   _   ___ | | __
 / __|| | | || '_ \ | | / _ \| __|| '__|| | | | / __|| |/ /
| (__ | |_| || |_) || ||  __/| |_ | |   | |_| || (__ |   <
 \___| \__,_||_.__/ |_| \___| \__||_|    \__,_| \___||_|\_\
						  Slackware

EOF

# script to turn off the LED blinking
cp $SRC/scripts/disable_led.sh $DEST/output/sdcard/bin/disable_led.sh

# make it executable
chmod +x $DEST/output/sdcard/bin/disable_led.sh
# and startable on boot
echo disable_led.sh > $DEST/output/sdcard/etc/rc.d/rc.local

# scripts for autoresize at first boot from cubian
cp $SRC/scripts/resize2fs-arch.sh $DEST/output/sdcard/root/resize2fs-root.sh
# make it executable
chmod +x $DEST/output/sdcard/root/resize2fs-root.sh
# and startable on boot just execute it once not on every boot!!!
#echo cubian-resize2fs > $DEST/output/sdcard/etc/rc.conf

# script to install to NAND
cp $SRC/scripts/nand-install.sh $DEST/output/sdcard/root
cp $SRC/bin/nand1-boot-cubietruck-arch.tgz $DEST/output/sdcard/root

# install and configure locales
#echo LANG='$DEST_LANG'.UTF-8 > $DEST/output/sdcard/etc/default.conf
#echo KEYMAP=us > $DEST/output/sdcard/etc/vconsole.conf
#use this command when System runs
# sudo timedatectl set-timezone Zone/SubZone
# when setup preferred gui like openbox then use loadkeys de

# i recommend you to change this urgently + add a proper user for the System!!!
# default passwort for user "root" is "root"
#echo 1234;echo 1234; | passwd root

# set hostname
echo darkstar > $DEST/output/sdcard/etc/HOSTNAME

### declare root partition in fstab
echo '/dev/mmcblk0p1	/	ext4	defaults		1	1' >> $DEST/output/sdcard/etc/fstab

### mount /tmp as tmpfs
echo 'tmpfs	/tmp	tmpfs	defaults,nosuid,size=30%	0	0' >> $DEST/output/sdcard/etc/fstab

### Optional /var/log
#echo 'tmpfs /var/log  tmpfs   defaults,nosuid   0   0' >> $DEST/output/sdcard/etc/fstab

##disable IPV6 and reduce timeout from 30s to 5 on dhcp daemon

#echo "ipv4only" >> /etc/dhcpcd.conf
#echo "noipv6rs" >> /etc/dhcpcd.conf
echo "timeout 5" >> /etc/dhcpcd.conf




# load modules you may load them per sysctl
cat >> $DEST/output/sdcard/etc/rc.d/rc.modules <<EOT
#!/bin/sh

/sbin/modprobe hci_uart
/sbin/modprobe gpio_sunxi
/sbin/modprobe bcmdhd
/sbin/modprobe ump
/sbin/modprobe mali
#/sbin/modprobe sunxi_gmac
EOT

# edit this to your personal needs/network configs take the ones from /etc/netctl/examples/ folder
# create interfaces configuration
#cat > $DEST/output/sdcard/etc/netctl/interfaces/eth0 <<EOT
#auto eth0
#allow-hotplug eth0
#iface eth0 inet dhcp
#        hwaddress ether #for AP use
#
#EOT

#use wifi-menu wlan0 to configure
#cat > $DEST/output/sdcard/etc/netctl/wlan0 <<EOT
#auto wlan0
#allow-hotplug wlan0
#iface wlan0 inet dhcp
#    wpa-ssid SSID
#    wpa-psk xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# to generate proper encrypted key: wpa_passphrase yourSSID yourpassword

#EOT

# create interfaces if you want to have AP. /etc/modules must be: bcmdhd op_mode=2
#cat <<EOT >> $DEST/output/sdcard/etc/network/interfaces.hostapd
#auto lo br0
#iface lo inet loopback

#allow-hotplug eth0
#iface eth0 inet manual

#allow-hotplug wlan0
#iface wlan0 inet manual

#iface br0 inet dhcp
#bridge_ports eth0 wlan0
#hwaddress ether # will be added at first boot
#EOT

# enable serial console (Debian/sysvinit way)
#echo T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100 >> $DEST/output/sdcard/etc/inittab

#remove the preconfigured boot from the image and use the one we want
rm -rf $DEST/output/sdcard/boot/
mkdir -p $DEST/output/sdcard/boot/
cp $DEST/output/uEnv.txt $DEST/output/sdcard/boot/
cp $DEST/linux-sunxi/arch/arm/boot/uImage $DEST/output/sdcard/boot/

# copy proper bin file
if [ $DISPLAY = 4 ]; then
    cp $DEST/output/script-vga.bin $DEST/output/sdcard/boot/script.bin
else
    cp $DEST/output/script-hdmi.bin $DEST/output/sdcard/boot/script.bin
fi

cp -R $DEST/linux-sunxi/output/lib/modules $DEST/output/sdcard/lib/
cp -R $DEST/linux-sunxi/output/lib/firmware/ $DEST/output/sdcard/lib/

# USB redirector tools http://www.incentivespro.com
#cd $DEST
#wget http://www.incentivespro.com/usb-redirector-linux-arm-eabi.tar.gz
#tar xvfz usb-redirector-linux-arm-eabi.tar.gz
#rm usb-redirector-linux-arm-eabi.tar.gz
#cd $DEST/usb-redirector-linux-arm-eabi/files/modules/src/tusbd
#make -j2 ARCH=arm CROSS_COMPILE=$CROSS_COMPILE KERNELDIR=$DEST/linux-sunxi/
# configure USB redirector
#sed -e 's/%INSTALLDIR_TAG%/\/usr\/local/g' $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd > $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1
#sed -e 's/%PIDFILE_TAG%/\/var\/run\/usbsrvd.pid/g' $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1 > $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
#sed -e 's/%STUBNAME_TAG%/tusbd/g' $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd > $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1
#sed -e 's/%DAEMONNAME_TAG%/usbsrvd/g' $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1 > $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
#chmod +x $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
# copy to root
#cp $DEST/usb-redirector-linux-arm-eabi/files/usb* $DEST/output/sdcard/usr/local/bin/
#cp $DEST/usb-redirector-linux-arm-eabi/files/modules/src/tusbd/tusbd.ko $DEST/output/sdcard/usr/local/bin/
#cp $DEST/usb-redirector-linux-arm-eabi/files/rc.usbsrvd $DEST/output/sdcard/etc/modules-load.d/
# started by default

# hostapd from testing binary replace.
# cd $DEST/output/sdcard/usr/sbin/
# tar xvfz $SRC/bin/hostapd21.tgz
# cp $SRC/config/hostapd.conf $DEST/output/sdcard/etc/

# sunxi-tools
cd $DEST/sunxi-tools
make clean
make -j2 'fex2bin' CC=${CROSS_COMPILE}gcc
make -j2 'bin2fex' CC=${CROSS_COMPILE}gcc
make -j2 'nand-part' CC=${CROSS_COMPILE}gcc

mkdir -p $DEST/output/sdcard/usr/bin/
cp fex2bin $DEST/output/sdcard/usr/bin/
cp bin2fex $DEST/output/sdcard/usr/bin/
cp nand-part $DEST/output/sdcard/usr/bin/

# umount images
umount $DEST/output/sdcard/
losetup -d $LOOP1
losetup -d $LOOP0
sync

# compress image
gzip $DEST/output/*.raw
