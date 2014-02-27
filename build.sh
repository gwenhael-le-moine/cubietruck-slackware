#!/bin/bash

set -e

# --- Configuration -------------------------------------------------------------
#change to your needs
IMG_NAME=${IMG_NAME:-"SlackwareARM_cubitruck"}
VERSION=${VERSION:-0.2}
COMPILE=${COMPILE:-"true"}
DEST=${DEST:-~/cubieslack}
DISPLAY=${DISPLAY:-"HDMI"}  # "HDMI" or "VGA"
IMAGE_SIZE_MB=${IMAGE_SIZE_MB:-2000}
SLACKWARE_VERSION=${SLACKWARE_VERSION:-14.1}
ROOTFS_VERSION=${ROOTFS_VERSION:-04Nov13}
#CONFIG_HZ=${CONFIG_HZ:-300HZ}  # 250HZ, 300HZ or 1000HZ
TOOLCHAIN_VERSION=${TOOLCHAIN_VERSION:-4.8-2013.10}
TOOLCHAIN_URL_RANDOM_NUMBER=${TOOLCHAIN_URL_RANDOM_NUMBER:-155358238}

# --- Script --------------------------------------------------------------------
CWD=$(pwd)

mkdir -p $DEST

#Requires root ..
if [ "$UID" -ne 0 ]; then
    echo "Please run as root"
fi

echo "Building Cubietruck-Slackware in $DEST from $CWD"
sleep 3

#--------------------------------------------------------------------------------
# Downloading necessary files for building - aka Toolchain
#--------------------------------------------------------------------------------
echo "------ Downloading cross-compiler"
#Read this for further information if you run into problems with gcc compiler
#http://linux-sunxi.org/Toolchain

wget -c https://launchpadlibrarian.net/$TOOLCHAIN_URL_RANDOM_NUMBER/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux.tar.xz -O $CWD/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux.tar.xz
tar xf $CWD/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux.tar.xz

CROSS_COMPILE=$PWD/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux/bin/arm-linux-gnueabihf-

#--------------------------------------------------------------------------------
# Preparing output / destination files
#--------------------------------------------------------------------------------
echo "------ Clone / Pull sources and patch"
mkdir -p $DEST/output
cp output/uEnv.txt $DEST/output

# Boot loader
if [ -d "$DEST/u-boot-sunxi" ]; then
    ( cd $DEST/u-boot-sunxi;
      git pull )
else
    git clone https://github.com/cubieboard/u-boot-sunxi $DEST/u-boot-sunxi

    # Applying Patch for 2gb memory
    patch -f $DEST/u-boot-sunxi/include/configs/sunxi-common.h < $CWD/patch/memory.patch || true
fi

# Allwinner tools
if [ -d "$DEST/sunxi-tools" ]; then
    ( cd $DEST/sunxi-tools;
      git pull )
else
    git clone https://github.com/linux-sunxi/sunxi-tools.git $DEST/sunxi-tools
fi

# Hardware configurations
if [ -d "$DEST/cubie_configs" ]; then
    ( cd $DEST/cubie_configs;
      git pull )
else
    git clone https://github.com/cubieboard/cubie_configs $DEST/cubie_configs

    # Applying Patch for high load. Could cause troubles with USB OTG port
    sed -e 's/usb_detect_type     = 1/usb_detect_type     = 0/g' $DEST/cubie_configs/sysconfig/linux/cubietruck.fex > $DEST/cubie_configs/sysconfig/linux/ct.fex

    # Prepare fex files for VGA & HDMI
    sed -e 's/screen0_output_type.*/screen0_output_type     = 3/g' $DEST/cubie_configs/sysconfig/linux/ct.fex > $DEST/cubie_configs/sysconfig/linux/ct-hdmi.fex
    sed -e 's/screen0_output_type.*/screen0_output_type     = 4/g' $DEST/cubie_configs/sysconfig/linux/ct.fex > $DEST/cubie_configs/sysconfig/linux/ct-vga.fex
fi

# Patwood's kernel 3.4.75+
if [ -d "$DEST/linux-sunxi" ]; then
    ( cd $DEST/linux-sunxi;
      git pull -f )
else
    git clone https://github.com/patrickhwood/linux-sunxi $DEST/linux-sunxi

    ###PATCH kernel CONFIG_HZ, Arm dfault is hardcoded 100hz (10ms latency!). For mulitimedia and desktop a higher frequency is recomended.
    #test -f $CWD/patch/$CONFIG_HZ.patch && patch -f $DEST/linux-sunxi/arch/arm/Kconfig < $CWD/patch/$CONFIG_HZ.patch
fi

#--------------------------------------------------------------------------------
# Compiling everything
#--------------------------------------------------------------------------------
echo "------ Compiling kernel boot loaderb"

# Copying Kernel config
cp $CWD/config/kernel.config $DEST/linux-sunxi/

echo "------ Compiling boot loader"
cd $DEST/u-boot-sunxi
make clean
make -j2 'cubietruck' CROSS_COMPILE=$CROSS_COMPILE
make HOSTCC=gcc CROSS_COMPILE='' tools
PATH=$PATH:$DEST/u-boot-sunxi/tools/

echo "------ Compiling sunxi tools"
cd $DEST/sunxi-tools
make clean fex2bin bin2fex

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
    ( cd $DEST/linux-sunxi/firmware;
      unzip -o $CWD/bin/ap6210.zip )

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

# create image and mount image to next free loop device
dd if=/dev/zero of=${IMG_NAME}-${VERSION}_rootfs_SD.raw bs=1M count=$IMAGE_SIZE_MB

LOOP0=$(losetup -f)
losetup $LOOP0 ${IMG_NAME}-${VERSION}_rootfs_SD.raw

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
wget -c ftp://ftp.arm.slackware.com/slackwarearm/slackwarearm-devtools/minirootfs/roots/slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz -O $CWD/slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz
tar xf $CWD/slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz

cat > $DEST/output/sdcard/etc/motd <<EOF
	      _      _        _                       _
  ___  _   _ | |__  (_)  ___ | |_  _ __  _   _   ___ | | __
 / __|| | | || '_ \ | | / _ \| __|| '__|| | | | / __|| |/ /
| (__ | |_| || |_) || ||  __/| |_ | |   | |_| || (__ |   <
 \___| \__,_||_.__/ |_| \___| \__||_|    \__,_| \___||_|\_\
						  Slackware

EOF

# script to turn off the LED blinking
cp $CWD/scripts/disable_led.sh $DEST/output/sdcard/bin/disable_led.sh

# make it executable
chmod +x $DEST/output/sdcard/bin/disable_led.sh

cat <<EOF >> $DEST/output/sdcard/etc/rc.d/rc.local

# Uncomment the following line to turn off the leds after booting
# /bin/disable_led.sh
EOF

# scripts for autoresize at first boot from cubian
cp $CWD/scripts/resize2fs-arch.sh $DEST/output/sdcard/root/resize2fs-root.sh
# make it executable
chmod +x $DEST/output/sdcard/root/resize2fs-root.sh

# set hostname
echo darkstar > $DEST/output/sdcard/etc/HOSTNAME

# setup fstab
### declare root partition in fstab
echo '/dev/mmcblk0p1	/	ext4	defaults		1	1' >> $DEST/output/sdcard/etc/fstab
### mount /tmp as tmpfs
echo 'tmpfs	/tmp	tmpfs	defaults,nosuid,size=30%	0	0' >> $DEST/output/sdcard/etc/fstab

# modules to load
cat >> $DEST/output/sdcard/etc/rc.d/rc.modules <<EOT
#!/bin/sh

/sbin/modprobe hci_uart
/sbin/modprobe gpio_sunxi
/sbin/modprobe bcmdhd
/sbin/modprobe ump
/sbin/modprobe mali
#/sbin/modprobe sunxi_gmac
EOT

#remove the preconfigured boot from the image and use the one we want
rm -rf $DEST/output/sdcard/boot/
mkdir -p $DEST/output/sdcard/boot/
cp $DEST/output/uEnv.txt $DEST/output/sdcard/boot/
cp $DEST/linux-sunxi/arch/arm/boot/uImage $DEST/output/sdcard/boot/

# copy proper bin file
case $DISPLAY in
    "VGA")				# VGA
	cp $DEST/output/script-vga.bin $DEST/output/sdcard/boot/script.bin
	;;
    "HDMI")				# HDMI
	cp $DEST/output/script-hdmi.bin $DEST/output/sdcard/boot/script.bin
	;;
    *) exit 1
esac

cp -R $DEST/linux-sunxi/output/lib/modules $DEST/output/sdcard/lib/
cp -R $DEST/linux-sunxi/output/lib/firmware/ $DEST/output/sdcard/lib/

# umount images
umount $DEST/output/sdcard/
losetup -d $LOOP1
losetup -d $LOOP0
sync

# compress image
gzip $DEST/output/*.raw
