#!/bin/bash
#
# This script formats the Cubietruck NAND flash and 
# copies your existing ArchLinux SD card installation to NAND
#
# The script is based on the original Debian script. 
# It's improved and adapted to work on ArchLinux for Cubietruck
#   
# Revision 2.0  14/02/2014 -- Klaus Schulz aka soundcheck @ cubieforums.com
#
#
###################################################################################
###################################################################################

# Check if user is root
if [ $(id -u) != "0" ]; then
    echo "Error: You must be root to run this script."
    exit 1
fi

###PARAMS##########################################################################
EXCLUDE=/root/nand-install-exclude ## rsync exclude
FLAG=/root/nand-install.flag
LOG=/root/nand-install.log
SYNCMOUNT1=/mnt/nand1
SYNCMOUNT2=/mnt/nand2

ARCHBOOTFILES=/root/nand1-boot-cubietruck-arch.tgz

###################################################################################

## applications required to get the job done
APPS=( nand-part mkfs.vfat mkfs.ext4 rsync tune2fs e2fsck )


## rsync exclude file for root fs
cat > $EXCLUDE <<EOF
/dev/*
/proc/*
/sys/*
/media/*
/mnt/*
/run/*
/tmp/*
EOF


## umount sync directory -- just in case it's still mounted
exec 2>/dev/null
umount $SYNCMOUNT1 
umount $SYNCMOUNT2
exec 2>&1



echo "
################################################################################################
## This script will initialize the entire NAND flash of your Cubietruck and 
## install your Archlinux SD installation.
##
## All existing data on your NAND flash will be lost!! You run the script at your own risk!
## 
## You know what you're doing ??!!??
################################################################################################

"
read -p "Proceed (y/n)?" -n 1 -r
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 0 ;


### check and install all apps required to run the process
if [ ! -f $FLAG ]; then

  echo "Checking required applications"

  pacman -S --noconfirm dosfstools rsync || exit 1  

  for i in ${APPS[@]} ; do
    which $i >/dev/null 2>&1 || { echo "Supporting app $i not found. Please install $i first." ; exit 1 ; } ;
  done

  test -f $ARCHBOOTFILES || { echo "Supporting $ARCHBOOTFILES not found. Please check." ; exit 1 ; } ;

fi


### partitioning nand
if [ ! -f $FLAG ]; then
   echo "Partitioning NAND with nand-part"
   touch $FLAG
   (echo y;) | nand-part -f a20 /dev/nand 32768 'bootloader 32768' 'rootfs 0' >$LOG
   echo
   echo "###################################################################################################################"
   read -p "The system will be rebooted now. Restart this script after reboot to continue the process! Press key to continue" -n 1 -r
   echo "###################################################################################################################"
   
   shutdown -r now
   exit 0
fi

### formatting nand
echo "Formatting and optimizing NAND root and boot fs... ...it'll take take a few seconds"

mkfs.vfat /dev/nand1 >$LOG
mkfs.ext4 /dev/nand2 >$LOG
tune2fs -o journal_data_writeback /dev/nand2 >$LOG
tune2fs -O ^has_journal /dev/nand2 >$LOG
e2fsck -f /dev/nand2

### rsync boot fs
echo "rSyncing boot fs to /dev/nand1... ...it'll take a few seconds"
test -d $SYNCMOUNT1 || mkdir -p $SYNCMOUNT1
test -d $SYNCMOUNT2 || mkdir -p $SYNCMOUNT2

mount /dev/nand1 $SYNCMOUNT1 && {

  ##TODO nand1 runs out of space very quickly, it might needs a verification beforehand 
  tar xfz $ARCHBOOTFILES -C $SYNCMOUNT1/
  rsync -aH /boot/ $SYNCMOUNT1
  # boot dev needs to be adapted in uEnv.txt
  sed -i 's/root=\/dev\/mmcblk0p1/nand_root=\/dev\/nand2/g' $SYNCMOUNT1/uEnv.txt 
  sync
  umount $SYNCMOUNT1
}

### rsync root fs
echo "rSyncing root fs to /dev/nand2... ...it'll take several minutes"

mount /dev/nand2 $SYNCMOUNT2 && {
 rsync -aH --exclude-from=$EXCLUDE / $SYNCMOUNT2
 sync
}

umount $SYNCMOUNT1
umount $SYNCMOUNT2

###cleanup
rm $FLAG
rm $EXCLUDE
echo
echo
echo "##########################################################################################"
echo "## Done. Shutdown your system, remove SD card and enjoy your nand based Archlinux system!"
echo "##########################################################################################"

exit 0
