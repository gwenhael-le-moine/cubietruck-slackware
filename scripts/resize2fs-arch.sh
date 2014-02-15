#!/bin/bash
#
#
# Script to resize the partition and filesystem on SD card for 
# Archlinux - Cubietruck
#
# Written by Klaus Schulz (soundcheck @ cubieforum.com)
# 
# Use script at your own risk. There is a high risk that your loose your data 
# by using the script, since it repartitions your media in realtime (mounted)
#
#####################################################################################

REVISION=1.0
DATE=02132014 


DISKID=mmcblk0
PARTID=mmcblk0p1

resizepartition() {
echo "******Resizing partition******************************"
echo

sync

##### fdisk commands
#p      print (check if first sector @2048 !! very important, if not all data ar elost if you continue !!!)
#d      delete partition (just the table!)
#n      new partition
#p      primary partition
#1      partition number
#<ret>  confirm default first sector @ 2048
#<ret>  confirm default last sector @ max
#p      print to verify new setup
#w      write to disk
#####

FIRSTSECTOR="$(( echo p) | fdisk /dev/$DISKID | grep $PARTID | sed "s/\*//g" | tr -s " " | cut -f 2 -d " " )"
( echo d; echo n; echo p; echo 1; echo $FIRSTSECTOR; echo; echo w; ) | fdisk /dev/$DISKID
shutdown -r now    
}

resizefs() {
echo "******Resizing filesystem******************************"
echo

resize2fs -p /dev/$PARTID
}


help() {
echo "
###############################################
Resizing Tool for Partion and Filesystem 
Applicable to ArchLinux on Cubietruck.

Revision $REVISION

Warning: 
You might loose all your data by running this
script. Run at your own risk!!!!
###############################################
Options:

-p  : resizes mounted!! partition and reboots
-f  : resizes filesystem
-h  : help

###############################################
"
}

#####main################################################################################################

case $1 in 

   p) resizepartition
      ;;
   f) resizefs
      ;;
   *) help
      ;;
esac


exit 0
