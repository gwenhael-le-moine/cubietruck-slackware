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

REVISION=2.0
DATE=02152014 


DISCID=mmcblk0
PARTID=mmcblk0p1



test -b /dev/$DISCID || { echo "SD device /dev/$DISCID can not be identifed. Please verify." ; exit 1 ;  } ;



resizepartition() {
echo "******Resizing partition******************************"
echo

sync

FIRSTSECTOR="$(( echo p) | fdisk "/dev/$DISCID" | grep $PARTID | sed "s/\*//g" | tr -s " " | cut -f 2 -d " " )"
#echo $FIRSTSECTOR
( echo d; echo n; echo p; echo 1; echo $FIRSTSECTOR; echo; echo w; ) | fdisk /dev/$DISCID
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
FS partitioning and resizing tool  
for SD card
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

   -p) resizepartition
      ;;
   -f) resizefs
      ;;
   *) help
      ;;
esac


exit 0
