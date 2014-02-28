#!/bin/bash

set -e

# Requires root ..
if [ "$UID" -ne 0 ]; then
    echo "Please run as root"
fi

# --- Configuration -------------------------------------------------------------
IMG_NAME=${IMG_NAME:-"SlackwareARM_cubitruck"}
VERSION=${VERSION:-0.2}
COMPILE=${COMPILE:-"true"}
DEST=${DEST:-~/cubieslack}
CUBIETRUCK_DISPLAY=${CUBIETRUCK_DISPLAY:-"HDMI"}  # "HDMI" or "VGA"
IMAGE_SIZE_MB=${IMAGE_SIZE_MB:-2000}
SLACKWARE_VERSION=${SLACKWARE_VERSION:-14.1}
ROOTFS_VERSION=${ROOTFS_VERSION:-04Nov13}
TOOLCHAIN_VERSION=${TOOLCHAIN_VERSION:-4.8-2013.10}
TOOLCHAIN_URL_RANDOM_NUMBER=${TOOLCHAIN_URL_RANDOM_NUMBER:-155358238}

# commandline arguments processing
while [ "x$1" != "x" ]
do
    case "$1" in
	-c | --compile )
	    shift
	    COMPILE="true"
	    ;;
	-dc | --dont-compile )
	    shift
	    COMPILE="false"
	    ;;
	-d | --display )
	    shift
	    CUBIETRUCK_DISPLAY=$1
	    shift
	    ;;
	-gz | --compress )
	    shift
	    COMPRESS="true"
	    ;;
	-n | --image-name )
	    shift
	    IMG_NAME=$1
	    shift
	    ;;
	-r | --rootfs-version )
	    shift
	    ROOTFS_VERSION=$1
	    shift
	    ;;
	-o | --output )
	    shift
	    DEST=$1
	    shift
	    ;;
	-v | --image-version )
	    shift
	    VERSION=$1
	    shift
	    ;;
	-xv | --toolchain-version )
	    shift
	    TOOLCHAIN_VERSION=$1
	    shift
	    ;;
	-xumn | --toolchain-url-magic-number )
	    shift
	    TOOLCHAIN_URL_RANDOM_NUMBER=$1
	    shift
	    ;;

	-h | --help )
	    echo -e "Usage: run as root: $0 <options>"
	    echo -e "Options:"
	    echo -e "\t-c | --compile"
	    echo -e "\t-dc | --dont-compile"
	    echo -e "\t-d | --display [\"HDMI\"|\"VGA\"] (default: $CUBIETRUCK_DISPLAY)"
	    echo -e "\t-n | --image-name [\"nom\"] (default: $IMG_NAME)"
	    echo -e "\t-r | --rootfs-version [\"version number\"] (default: $ROOTFS_VERSION)"
	    echo -e "\t-o | --output [/directory/] (default: $DEST)"
	    echo -e "\t-v | --image-version [\"version number\"] (default: $VERSION)"
	    echo -e "\t-xv | --toolchain-version [\"version number\"] (default: $TOOLCHAIN_VERSION)"
	    echo -e "\t-xumn | --toolchain-url-magic-number [\"magic number\"] (default: $TOOLCHAIN_URL_RANDOM_NUMBER)"

	    exit 0
	    ;;
    esac
done

# --- Script --------------------------------------------------------------------
CWD=$(pwd)
BINARIES_DIR=$CWD/binaries

mkdir -p $DEST

echo "Building Cubietruck-Slackware in $DEST from $CWD"

if [ "$COMPILE" = "true" ]; then

    mkdir -p $BINARIES_DIR

    echo "--------------------------------------------------------------------------------"
    echo "Downloading necessary files for building - aka Toolchain"
    echo "--------------------------------------------------------------------------------"
    if $(uname -m | grep -q arm); then
	CROSS_COMPILE=''
    else
	#Read this for further information if you run into problems with gcc compiler
	#http://linux-sunxi.org/Toolchain
	if [ ! -e $PWD/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux/ ]; then
	    [ ! -e $CWD/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux.tar.xz ] && wget -c https://launchpadlibrarian.net/$TOOLCHAIN_URL_RANDOM_NUMBER/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux.tar.xz -O $CWD/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux.tar.xz
	    tar xf $CWD/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux.tar.xz
	fi

	CROSS_COMPILE=$PWD/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux/bin/arm-linux-gnueabihf-
    fi

    echo "--------------------------------------------------------------------------------"
    echo "Clone / Pull sources and patch"
    echo "--------------------------------------------------------------------------------"
    mkdir -p $DEST/output

    # Boot loader
    if [ -d "$DEST/u-boot-sunxi" ]; then
	( cd $DEST/u-boot-sunxi;
	  git pull )
    else
	git clone https://github.com/cubieboard/u-boot-sunxi $DEST/u-boot-sunxi

	# Applying Patch for 2gb memory
	patch -f $DEST/u-boot-sunxi/include/configs/sunxi-common.h < $CWD/patch/memory.patch || true
    fi
    echo "------ Compiling boot loader"
    ( cd $DEST/u-boot-sunxi
      make clean CROSS_COMPILE=$CROSS_COMPILE
      make -j2 'cubietruck' CROSS_COMPILE=$CROSS_COMPILE
      make HOSTCC=gcc CROSS_COMPILE='' tools

      mkdir -p $BINARIES_DIR/$(basename $(pwd))
      mv tools/mkimage $BINARIES_DIR/$(basename $(pwd))
    )

    # Allwinner tools
    if [ -d "$DEST/sunxi-tools" ]; then
	( cd $DEST/sunxi-tools;
	  git pull )
    else
	git clone https://github.com/linux-sunxi/sunxi-tools.git $DEST/sunxi-tools
    fi
    echo "------ Compiling sunxi tools"
    ( cd $DEST/sunxi-tools
      make clean
      make fex2bin bin2fex

      mkdir -p $BINARIES_DIR/$(basename $(pwd))
      mv fexc fex2bin bin2fex $BINARIES_DIR/$(basename $(pwd))
    )

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
    mkdir -p $BINARIES_DIR/cubie_configs
    $BINARIES_DIR/sunxi-tools/fex2bin $DEST/cubie_configs/sysconfig/linux/ct-vga.fex $BINARIES_DIR/cubie_configs/script-vga.bin
    $BINARIES_DIR/sunxi-tools/fex2bin $DEST/cubie_configs/sysconfig/linux/ct-hdmi.fex $BINARIES_DIR/cubie_configs/script-hdmi.bin

    # Patwood's kernel 3.4.75+
    if [ -d "$DEST/linux-sunxi" ]; then
	( cd $DEST/linux-sunxi;
	  git pull -f )
    else
	git clone https://github.com/patrickhwood/linux-sunxi $DEST/linux-sunxi
    fi
    echo "------ Compiling kernel"
    ( cd $DEST/linux-sunxi
      PATH=$PATH:$BINARIES_DIR/u-boot-sunxi/

      make clean

      # Adding wlan firmware to kernel source
      ( cd $DEST/linux-sunxi/firmware;
	unzip -o $CWD/bin/ap6210.zip )

      make -j2 ARCH=arm CROSS_COMPILE=$CROSS_COMPILE sun7i_defconfig

      # get proven config
      cp $CWD/config/kernel.config $DEST/linux-sunxi/.config
      make -j2 ARCH=arm CROSS_COMPILE=$CROSS_COMPILE uImage modules
      make -j2 ARCH=arm CROSS_COMPILE=$CROSS_COMPILE INSTALL_MOD_PATH=output modules_install
      make -j2 ARCH=arm CROSS_COMPILE=$CROSS_COMPILE INSTALL_HDR_PATH=output headers_install

      mkdir -p $BINARIES_DIR/$(basename $(pwd))
      cp $DEST/linux-sunxi/arch/arm/boot/uImage $BINARIES_DIR/$(basename $(pwd))
      cp -R $DEST/linux-sunxi/output/lib/modules $BINARIES_DIR/$(basename $(pwd))
      cp -R $DEST/linux-sunxi/output/lib/firmware/ $BINARIES_DIR/$(basename $(pwd))
    )
fi






echo "--------------------------------------------------------------------------------"
echo "Creating SD Image"
echo "--------------------------------------------------------------------------------"
cd $DEST/output

echo "create image and mount image to next free loop device"
dd if=/dev/zero of=${IMG_NAME}-${VERSION}_rootfs_SD.raw bs=1M count=$IMAGE_SIZE_MB

LOOP0=$(losetup -f)
losetup $LOOP0 ${IMG_NAME}-${VERSION}_rootfs_SD.raw

echo "------ Partitionning and mounting filesystem"
dd if=$DEST/u-boot-sunxi/u-boot-sunxi-with-spl.bin of=$LOOP0 bs=1024 seek=8

# create one partition starting at 2048 which is default
(echo n; echo p; echo 1; echo; echo; echo w) | fdisk $LOOP0 >> /dev/null || true

# just to make sure
partprobe $LOOP0

LOOP1=$(losetup -f)
# 2048 (start) x 512 (block size) = where to mount partition
losetup -o 1048576 $LOOP1 $LOOP0

echo "create filesystem"
mkfs.ext4 $LOOP1

echo "create mount point and mount image"
mkdir -p $DEST/output/sdcard/
mount $LOOP1 $DEST/output/sdcard/









echo "------ Get basic Slackware System"
cd $DEST/output/sdcard/
[ ! -e $CWD/slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz ] && wget -c ftp://ftp.arm.slackware.com/slackwarearm/slackwarearm-devtools/minirootfs/roots/slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz -O $CWD/slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz
tar xf $CWD/slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz

echo "Configuring Slackware"
cat > $DEST/output/sdcard/etc/motd <<EOF
	      _      _        _                       _
  ___  _   _ | |__  (_)  ___ | |_  _ __  _   _   ___ | | __
 / __|| | | || '_ \ | | / _ \| __|| '__|| | | | / __|| |/ /
| (__ | |_| || |_) || ||  __/| |_ | |   | |_| || (__ |   <
 \___| \__,_||_.__/ |_| \___| \__||_|    \__,_| \___||_|\_\
						  Slackware

EOF

echo "install script to turn off the LED blinking"
cp $CWD/scripts/disable_led.sh $DEST/output/sdcard/bin/disable_led.sh
chmod +x $DEST/output/sdcard/bin/disable_led.sh

cat <<EOF >> $DEST/output/sdcard/etc/rc.d/rc.local

# Uncomment the following line to turn off the leds after booting
# /bin/disable_led.sh
EOF

echo "scripts for autoresize at first boot from cubian"
cp $CWD/scripts/resize2fs-arch.sh $DEST/output/sdcard/root/resize2fs-root.sh
chmod +x $DEST/output/sdcard/root/resize2fs-root.sh

echo "set hostname"
echo darkstar > $DEST/output/sdcard/etc/HOSTNAME

echo "setup fstab"
### declare root partition in fstab
echo '/dev/mmcblk0p1	/	ext4	defaults		1	1' >> $DEST/output/sdcard/etc/fstab
### mount /tmp as tmpfs
echo 'tmpfs	/tmp	tmpfs	defaults,nosuid,size=30%	0	0' >> $DEST/output/sdcard/etc/fstab

echo "modules to load"
cat >> $DEST/output/sdcard/etc/rc.d/rc.modules <<EOT
#!/bin/sh

/sbin/modprobe hci_uart
/sbin/modprobe gpio_sunxi
/sbin/modprobe bcmdhd
/sbin/modprobe ump
/sbin/modprobe mali
#/sbin/modprobe sunxi_gmac
EOT





echo "remove the preconfigured boot and setup ours"
rm -rf $DEST/output/sdcard/boot/
mkdir -p $DEST/output/sdcard/boot/
cat <<EOF > $DEST/output/sdcard/boot/uEnv.txt
root=/dev/mmcblk0p1 ro
extraargs=console=tty0,115200 sunxi_no_mali_mem_reserve sunxi_g2d_mem_reserve=0 sunxi_ve_mem_reserve=0 hdmi.audio=EDID:0 disp.screen0_output_mode=EDID:1280x720p50 rootwait panic=10 rootfstype=ext4 rootflags=discard
panic=10 rootfstype=ext4 rootflags=discard
EOF

echo "setup video output"
echo $CUBIETRUCK_DISPLAY
case $CUBIETRUCK_DISPLAY in
    VGA)				# VGA
	cp $BINARIES_DIR/cubie_configs/script-vga.bin $DEST/output/sdcard/boot/script.bin
	;;
    HDMI)				# HDMI
	cp $BINARIES_DIR/cubie_configs/script-hdmi.bin $DEST/output/sdcard/boot/script.bin
	;;
    *) exit 1
esac

echo "Installing kernel"
cp $BINARIES_DIR/linux-sunxi/uImage $DEST/output/sdcard/boot/
cp -R $BINARIES_DIR/linux-sunxi/modules $DEST/output/sdcard/lib/
cp -R $BINARIES_DIR/linux-sunxi/firmware/ $DEST/output/sdcard/lib/

sync

sleep 3

echo "umount images"
umount -d -l $DEST/output/sdcard/
losetup -d $LOOP1
losetup -d $LOOP0

echo "cleaning"
rm -r $DEST/output/sdcard/

if [ "$COMPRESS" = "true" ]; then
    echo "compress image"
    xz -z $DEST/output/${IMG_NAME}-${VERSION}_rootfs_SD.raw
fi
