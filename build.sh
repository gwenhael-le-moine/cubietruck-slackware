#!/bin/bash

set -e

# Requires root ..
if [ "$UID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

CWD=$(pwd)

# --- Configuration -------------------------------------------------------------
IMG_NAME=${IMG_NAME:-"SlackwareARM_cubitruck"}
VERSION=${VERSION:-0.4}
COMPILE_BINARIES=${COMPILE_BINARIES:-"false"}
DOWNLOAD_BINARIES=${DOWNLOAD_BINARIES:-"true"}
CREATE_IMAGE=${CREATE_IMAGE:-"true"}
DEST=${DEST:-$CWD/dist}
CUBIETRUCK_DISPLAY=${CUBIETRUCK_DISPLAY:-"HDMI"}
IMAGE_SIZE_MB=${IMAGE_SIZE_MB:-2000}
SLACKWARE_VERSION=${SLACKWARE_VERSION:-current}
ROOTFS_VERSION=${ROOTFS_VERSION:-06Jan15}
TOOLCHAIN_VERSION=${TOOLCHAIN_VERSION:-4.8-2013.10}
TOOLCHAIN_URL_RANDOM_NUMBER=${TOOLCHAIN_URL_RANDOM_NUMBER:-155358238}

REPO_UBOOT=${REPO_UBOOT:-https://github.com/cubieboard/u-boot-sunxi}
REPO_SUNXI_TOOLS=${REPO_SUNXI_TOOLS:-https://github.com/linux-sunxi/sunxi-tools.git}
REPO_CONFIGS=${REPO_CONFIGS:-https://github.com/cubieboard/cubie_configs}
REPO_LINUX=${REPO_LINUX:-https://github.com/linux-sunxi/linux-sunxi}
# REPO_LINUX=${REPO_LINUX:-https://github.com/cubieboard2/linux-sunxi}
# REPO_LINUX=${REPO_LINUX:-https://github.com/cubieboard/linux-sunxi}

PACKAGE_BINARIES="false"

BINARIES_DIR=$CWD/binaries

# --- Functions ----------------------------------------------------------------
function prepare_dest() {
    mkdir -p $DEST
}

function download_and_install_binaries() {
    echo ". install binaries"
    mkdir -p $DEST/image/sdcard/
    cd $DEST/image/sdcard/
    if [ ! -e $CWD/binaries-$VERSION.tar.xz ]; then
	echo ". . downloading binaries"
	wget -c https://bitbucket.org/gwenhael/cubietruck-slackware/downloads/binaries-$VERSION.tar.xz \
	     -O $CWD/binaries-$VERSION.tar.xz
    fi
    echo ". . extracting binaries"
    tar xf $CWD/binaries-$VERSION.tar.xz
}

function setup_x_toolchain() {
    echo ". setting up cross-compiler if needed"
    if $(uname -m | grep -q arm); then
	echo ". . ARM host detected, no cross-compiler needed"
	CROSS_COMPILE=''
    else
	#Read this for further information if you run into problems with gcc compiler
	#http://linux-sunxi.org/Toolchain
	if [ ! -e $PWD/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux/ ]; then
	    if [ ! -e $CWD/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux.tar.xz ]; then
		echo ". . downloading cross-compiler"
		wget -c https://launchpadlibrarian.net/$TOOLCHAIN_URL_RANDOM_NUMBER/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux.tar.xz \
		     -O $CWD/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux.tar.xz
	    fi
	    echo ". . installing cross-compiler locally"
	    tar xf $CWD/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux.tar.xz
	fi

	CROSS_COMPILE=$PWD/gcc-linaro-arm-linux-gnueabihf-${TOOLCHAIN_VERSION}_linux/bin/arm-linux-gnueabihf-
    fi
}

function clone_pull_patch_sources() {
    mkdir -p $DEST/image

    # Boot loader
    if [ -d "$DEST/u-boot-sunxi" ]; then
	echo ". . updating u-boot-sunxi"
	( cd $DEST/u-boot-sunxi;
	  git pull )
    else
	echo ". . cloning u-boot-sunxi"
	git clone $REPO_UBOOT $DEST/u-boot-sunxi
    fi

    # Allwinner tools
    if [ -d "$DEST/sunxi-tools" ]; then
	echo ". . updating sunxi-tools"
	( cd $DEST/sunxi-tools;
	  git pull )
    else
	echo ". . cloning sunxi-tools"
	git clone $REPO_SUNXI_TOOLS $DEST/sunxi-tools
    fi

    # Hardware configurations
    if [ -d "$DEST/cubie_configs" ]; then
	echo ". . updating cubie_configs"
	( cd $DEST/cubie_configs;
	  git pull )
    else
	echo ". . cloning sunxi-tools"
	git clone $REPO_CONFIGS $DEST/cubie_configs

	echo ". . patching sunxi-tools"
	# Applying Patch for high load. Could cause troubles with USB OTG port
	sed -e 's/usb_detect_type     = 1/usb_detect_type     = 0/g' $DEST/cubie_configs/sysconfig/linux/cubietruck.fex > $DEST/cubie_configs/sysconfig/linux/ct.fex

	# Prepare fex files for VGA & HDMI
	sed -e 's/screen0_output_type.*/screen0_output_type     = 3/g' $DEST/cubie_configs/sysconfig/linux/ct.fex > $DEST/cubie_configs/sysconfig/linux/ct-hdmi.fex
	sed -e 's/screen0_output_type.*/screen0_output_type     = 4/g' $DEST/cubie_configs/sysconfig/linux/ct.fex > $DEST/cubie_configs/sysconfig/linux/ct-vga.fex
    fi

    if [ -d "$DEST/linux-sunxi" ]; then
	echo ". . updating linux-sunxi"
	( cd $DEST/linux-sunxi;
	  git pull -f )
    else
	echo ". . updating linux-sunxi"
	git clone $REPO_LINUX $DEST/linux-sunxi
    fi
}

function clean_sources() {
    echo ". cleaning sources"
    for i in u-boot-sunxi sunxi-tools linux-sunxi; do
	echo ". . cleaning $i"
	( cd $DEST/$i
	  make clean CROSS_COMPILE=$CROSS_COMPILE )
    done
}

function compile() {
    echo ". compiling binaries and installing them into $BINARIES_DIR"
    mkdir -p $BINARIES_DIR

    ( cd $DEST/u-boot-sunxi
      cp $CWD/config/kernel.config $DEST/u-boot-sunxi/include/linux/config.h
      echo ". . compiling u-boot-sunxi"
      make -j2 'cubietruck' CROSS_COMPILE=$CROSS_COMPILE
      make HOSTCC=gcc CROSS_COMPILE='' tools

      echo ". . installing u-boot-sunxi in $BINARIES_DIR"
      mkdir -p $BINARIES_DIR/$(basename $(pwd))
      mv tools/mkimage $BINARIES_DIR/$(basename $(pwd))
    )

    ( cd $DEST/sunxi-tools
      echo ". . compiling sunxi-tools"
      make fex2bin bin2fex

      echo ". . installing sunxi-tools in $BINARIES_DIR"
      mkdir -p $BINARIES_DIR/$(basename $(pwd))
      mv fexc fex2bin bin2fex $BINARIES_DIR/$(basename $(pwd))
    )

    echo ". . installing cubie_configs in $BINARIES_DIR"
    mkdir -p $BINARIES_DIR/cubie_configs
    $BINARIES_DIR/sunxi-tools/fex2bin $DEST/cubie_configs/sysconfig/linux/ct-vga.fex $BINARIES_DIR/cubie_configs/script-vga.bin
    $BINARIES_DIR/sunxi-tools/fex2bin $DEST/cubie_configs/sysconfig/linux/ct-hdmi.fex $BINARIES_DIR/cubie_configs/script-hdmi.bin

    ( cd $DEST/linux-sunxi
      PATH=$PATH:$BINARIES_DIR/u-boot-sunxi/

      echo ". . adding ap6210 firmware to kernel"
      ( cd $DEST/linux-sunxi/firmware;
	unzip -o $CWD/firmwares/ap6210.zip )

      echo ". . compiling kernel"
      make -j2 ARCH=arm CROSS_COMPILE=$CROSS_COMPILE sun7i_defconfig

      # get proven config
      cp $CWD/config/kernel.config $DEST/linux-sunxi/.config
      make -j2 ARCH=arm CROSS_COMPILE=$CROSS_COMPILE uImage modules
      make -j2 ARCH=arm CROSS_COMPILE=$CROSS_COMPILE INSTALL_MOD_PATH=output modules_install
      make -j2 ARCH=arm CROSS_COMPILE=$CROSS_COMPILE INSTALL_HDR_PATH=output headers_install

      echo ". . installing kernel in $BINARIES_DIR"
      mkdir -p $BINARIES_DIR/$(basename $(pwd))
      cp $DEST/linux-sunxi/arch/arm/boot/uImage $BINARIES_DIR/$(basename $(pwd))
      cp -R $DEST/linux-sunxi/output/lib/modules $BINARIES_DIR/$(basename $(pwd))
      cp -R $DEST/linux-sunxi/output/lib/firmware/ $BINARIES_DIR/$(basename $(pwd))
    )
}

function pack_binaries() {
    echo ". packaging $BINARIES_DIR into $BINARIES_DIR"
    tar Jcf $BINARIES_DIR-$VERSION.tar.xz $BINARIES_DIR
}

function create_and_mount_image() {
    echo ". creating and mounting image"
    mkdir -p $DEST/image
    cd $DEST/image

    echo ". . create image and mount image to next free loop device"
    dd if=/dev/zero of=${IMG_NAME}-${VERSION}_rootfs_SD.raw bs=1M count=$IMAGE_SIZE_MB

    LOOP0=$(losetup -f)
    losetup $LOOP0 ${IMG_NAME}-${VERSION}_rootfs_SD.raw

    echo ". .  Partitionning and mounting filesystem"
    dd if=$DEST/u-boot-sunxi/u-boot-sunxi-with-spl.bin of=$LOOP0 bs=1024 seek=8

    # create one partition starting at 2048 which is default
    (echo n; echo p; echo 1; echo; echo; echo w) | fdisk $LOOP0 >> /dev/null || true

    # just to make sure
    partprobe $LOOP0

    LOOP1=$(losetup -f)
    # 2048 (start) x 512 (block size) = where to mount partition
    losetup -o 1048576 $LOOP1 $LOOP0

    echo ". . create filesystem"
    mkfs.ext4 $LOOP1

    echo ". . create mount point and mount image"
    mkdir -p $DEST/image/sdcard/
    mount $LOOP1 $DEST/image/sdcard/
}

function umount_image() {
    echo ". umount image"
    umount -d -l $DEST/image/sdcard/
    losetup -d $LOOP1
    losetup -d $LOOP0

    echo "cleaning"
    rm -r $DEST/image/sdcard/
}

function compress_image() {
    echo ". compress image"
    xz -z $DEST/image/${IMG_NAME}-${VERSION}_rootfs_SD.raw
}

function download_and_install_minirootfs() {
    echo ". install minirootds"
    cd $DEST/image/sdcard/
    if [ ! -e $CWD/slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz ]; then
	echo ". . downloading minirootfs"
	wget -c ftp://ftp.arm.slackware.com/slackwarearm/slackwarearm-devtools/minirootfs/roots/slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz \
	     -O $CWD/slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz
    fi
    echo ". . extracting minirootfs"
    tar xf $CWD/slack-$SLACKWARE_VERSION-miniroot_$ROOTFS_VERSION.tar.xz
}

function configure_slackwarearm() {
    echo ". configuring system"
    cat > $DEST/image/sdcard/etc/motd <<EOF
	      _      _        _                       _
  ___  _   _ | |__  (_)  ___ | |_  _ __  _   _   ___ | | __
 / __|| | | || '_ \ | | / _ \| __|| '__|| | | | / __|| |/ /
| (__ | |_| || |_) || ||  __/| |_ | |   | |_| || (__ |   <
 \___| \__,_||_.__/ |_| \___| \__||_|    \__,_| \___||_|\_\
						  Slackware

EOF

    echo ". . install script to turn off the LED blinking"
    cp $CWD/scripts/disable_led.sh $DEST/image/sdcard/bin/disable_led.sh
    chmod +x $DEST/image/sdcard/bin/disable_led.sh

    cat <<EOF >> $DEST/image/sdcard/etc/rc.d/rc.local

# Uncomment the following line to turn off the leds after booting
# /bin/disable_led.sh
EOF

    echo ". . copy script to expand filesystem to the whole card"
    cp $CWD/scripts/resize2fs-arch.sh $DEST/image/sdcard/root/resize2fs-root.sh
    chmod +x $DEST/image/sdcard/root/resize2fs-root.sh

    echo ". . set hostname"
    echo darkstar > $DEST/image/sdcard/etc/HOSTNAME

    echo ". . setup fstab"
    echo '/dev/mmcblk0p1	/	ext4	defaults		1	1' >> $DEST/image/sdcard/etc/fstab
    echo 'tmpfs	/tmp	tmpfs	defaults,nosuid,size=30%	0	0' >> $DEST/image/sdcard/etc/fstab
}

function install_kernel_and_boot() {
    echo ". install kernel and setup boot"
    echo ". . remove the preconfigured boot and setup ours"
    rm -rf $DEST/image/sdcard/boot/*

    TARGET=/image/sdcard
    if [ -x /sbin/makepkg ] && [ -x /sbin/installpkg ]; then
	mkdir -p $DEST/pkg-linux-sunxi/{boot,lib}/
	TARGET=/pkg-linux-sunxi
    fi

    echo ". . configure u-boot"
    cat <<EOF > $DEST$TARGET/boot/uEnv.txt
root=/dev/mmcblk0p1 ro rootwait
extraargs=console=tty0,115200 sunxi_no_mali_mem_reserve sunxi_g2d_mem_reserve=0 sunxi_ve_mem_reserve=0 hdmi.audio=EDID:0 disp.screen0_output_mode=EDID:1280x720p50 rootwait
panic=10 rootfstype=ext4 rootflags=discard
EOF

    echo ". . setup video output"
    cp $BINARIES_DIR/cubie_configs/script-*.bin $DEST$TARGET/boot/
    ( cd $DEST$TARGET/boot/
      [ -e script.bin ] && rm script.bin
      case $CUBIETRUCK_DISPLAY in
	  VGA) ln script-vga.bin script.bin
	       ;;
	  HDMI) ln script-hdmi.bin script.bin
		;;
      esac )

    echo ". . Installing kernel"
    cp $BINARIES_DIR/linux-sunxi/uImage $DEST$TARGET/boot/
    cp -R $BINARIES_DIR/linux-sunxi/modules $DEST$TARGET/lib/
    cp -R $BINARIES_DIR/linux-sunxi/firmware/ $DEST$TARGET/lib/

    echo ". . write rc.modules"
    mkdir -p $DEST$TARGET/etc/rc.d/
    cat >> $DEST$TARGET/etc/rc.d/rc.modules <<EOT
#!/bin/sh

/sbin/modprobe hci_uart
/sbin/modprobe gpio_sunxi
/sbin/modprobe bcmdhd
/sbin/modprobe ump
/sbin/modprobe mali
#/sbin/modprobe sunxi_gmac
EOT
    chmod +x $DEST$TARGET/etc/rc.d/rc.modules

    if [ -x /sbin/makepkg ] && [ -x /sbin/installpkg ]; then
	echo ". . build slackware package for kernel"
	mkdir -p $DEST/pkg-linux-sunxi/install/
	PRGNAM=linux-sunxi
	cat <<EOF > $DEST/pkg-linux-sunxi/install/slack-desc
$PRGNAM: $PRGNAM (Linux sunxi kernel)
$PRGNAM:
$PRGNAM: Linux is a clone of the operating system Unix, written from scratch by
$PRGNAM: Linus Torvalds with assistance from a loosely-knit team of hackers
$PRGNAM: across the Net. It aims towards POSIX and Single UNIX Specification
$PRGNAM: compliance.
$PRGNAM:
$PRGNAM: It has all the features you would expect in a modern fully-fledged Unix
$PRGNAM:
$PRGNAM: $REPO_LINUX
$PRGNAM:
EOF

	VERSION=$(cat $DEST/linux-sunxi/Makefile | grep "^VERSION" | sed "s|^VERSION = \(.*\)$|\1|g")
	VERSION=$VERSION.$(cat $DEST/linux-sunxi/Makefile | grep "^PATCHLEVEL" | sed "s|^PATCHLEVEL = \(.*\)$|\1|g")
	VERSION=$VERSION.$(cat $DEST/linux-sunxi/Makefile | grep "^SUBLEVEL" | sed "s|^SUBLEVEL = \(.*\)$|\1|g")
	# VERSION=$VERSION.$(cat $DEST/linux-sunxi/Makefile | grep "^EXTRAVERSION" | sed "s|^EXTRAVERSION = \(.*\)$|\1|g")
	ARCH=arm
	BUILD=1
	TAG=cyco

	( cd $DEST/pkg-linux-sunxi

	  makepkg -l y -c n $DEST/$PRGNAM-$VERSION-$ARCH-$BUILD$TAG.txz
	)

	installpkg --root $DEST/image/sdcard/ $DEST/$PRGNAM-$VERSION-$ARCH-$BUILD$TAG.txz
    fi
}

function clean_image() {
    rm $DEST/image/*
}

function clean_binaries() {
    rm -r $DEST/binaries/*
}


# commandline arguments processing
while [ "x$1" != "x" ]
do
    case "$1" in
	-b | --binaries )
	    shift
	    DOWNLOAD_BINARIES="true"
	    COMPILE_BINARIES="false"
	    ;;
	--clean )
	    shift
	    clean_sources
	    clean_binaries
	    clean_image
	    exit -1
	    ;;
	-c | --compile )
	    shift
	    COMPILE_BINARIES="true"
	    DOWNLOAD_BINARIES="false"
	    ;;
	-dc | --dont-compile )
	    shift
	    COMPILE_BINARIES="false"
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
	-i | --create-image )
	    shift
	    CREATE_IMAGE="true"
	    ;;
	-ni | --no-image )
	    shift
	    CREATE_IMAGE="false"
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
	-s | --image-size )
	    shift
	    IMAGE_SIZE_MB=$1
	    shift
	    ;;
	-o | --output )
	    shift
	    DEST=$1
	    shift
	    ;;
	--package-binaries )
	    shift
	    PACKAGE_BINARIES="true"
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
	    echo -e "\t--clean"
	    echo -e "\t\tclean sources, remove binaries and image"

	    echo -e "\t-b | --binaries"
	    echo -e "\t\tdownload and use pre-built binaries"

	    echo -e "\t-c | --compile"
	    echo -e "\t\tbuild binaries locally"

	    echo -e "\t-dc | --dont-compile (default)"
	    echo -e "\t\tskip compilation"

	    echo -e "\t-i | --create-image (default)"
	    echo -e "\t\tgenerate image"

	    echo -e "\t-ni | --no-image"
	    echo -e "\t\tskip image generation"

	    echo -e "\t-d | --display [\"HDMI\"|\"VGA\"] (default: $CUBIETRUCK_DISPLAY)"
	    echo -e "\t\tconfiguration image video output"

	    echo -e "\t-gz | --compress (default: no)"
	    echo -e "\t\tcompress image (takes time)"

	    echo -e "\t-n | --image-name [\"nom\"] (default: $IMG_NAME)"
	    echo -e "\t\tname the image"

	    echo -e "\t-r | --rootfs-version [\"version number\"] (default: $ROOTFS_VERSION)"
	    echo -e "\t\tversion of the minirootfs"

	    echo -e "\t-s | --image-size [size in MB] (default: $IMAGE_SIZE_MB)"
	    echo -e "\t\tsize of the image (see resizefs script in image)"

	    echo -e "\t-o | --output [/directory/] (default: $DEST)"
	    echo -e "\t\tdirectory where the image will be generated"

	    echo -e "\t--package-binaries"
	    echo -e "\t\tpackage compiled binaries into $BINARIES_DIR-$VERSION.tar.xz"
	    echo -e "\t\t(combine with --compile)"

	    echo -e "\t-v | --image-version [\"version number\"] (default: $VERSION)"
	    echo -e "\t\tversion the image"

	    echo -e "\t-xv | --toolchain-version [\"version number\"] (default: $TOOLCHAIN_VERSION)"
	    echo -e "\t-xumn | --toolchain-url-magic-number [\"magic number\"] (default: $TOOLCHAIN_URL_RANDOM_NUMBER)"
	    echo -e "\t\tversion of the cross-compiler"

	    exit 0
	    ;;
    esac
done

# --- Script --------------------------------------------------------------------
prepare_dest

if [ "$COMPILE_BINARIES" = "true" ]; then
    setup_x_toolchain
    clone_pull_patch_sources
    clean_sources
    compile
else
    if [ "$DOWNLOAD_BINARIES" = "true" ]; then
	download_and_install_binaries
    fi
fi

[ "$PACKAGE_BINARIES" = "true" ] && pack_binaries && exit -1

if [ ! -e $BINARIES_DIR ]; then
    echo "ERROR"
    echo "Necessary binaries files not present !"
    echo "Either run $0 --compile or download them from https://bitbucket.org/gwenhael/cubietruck-slackware/downloads"
    echo "and untar them here."

    exit 99
fi

if [ "$CREATE_IMAGE" = "true" ]; then
    create_and_mount_image
    download_and_install_minirootfs
    configure_slackwarearm
    install_kernel_and_boot
    umount_image
fi

[ "$COMPRESS" = "true" ] && compress_image
