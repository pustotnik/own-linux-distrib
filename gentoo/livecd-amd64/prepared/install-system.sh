#!/bin/bash

################################################
####### USER INPUT #############################
echo "Configuring installation. For default values press ENTER."
echo ""

echo -n "Select installation mode. Valid variants: device, partition (by default 'device'): "
read INSTALLMODE

if [ "${INSTALLMODE}" == "" ]; then
    INSTALLMODE="device"
fi

if [ "${INSTALLMODE}" == "device" ]; then

    echo "Target device for install."
    echo "ATTENTION!!! ALL DATA WILL BE LOST ON THIS DEVICE!"

    echo -n "Select target device for install (by default '/dev/sda'): "
    read DEV
    if [ "${DEV}" == "" ]; then
        DEV="/dev/sda"
    fi

    if ! [ -e ${DEV} ]; then
        echo "${DEV} is not exists, exit"
        exit 1
    fi

    if ! [ -b ${DEV} ]; then
        echo "${DEV} is not a block device, exit"
        exit 1
    fi


    echo -n "Select filesystem. Valid variants: reiserfs, ext4, xfs (by default 'reiserfs'): "
    read FSTYPE
    if [ "${FSTYPE}" == "" ]; then
        FSTYPE="reiserfs"
    fi

    if [ "${FSTYPE}" != "reiserfs" ] && [ "${FSTYPE}" != "ext4" ] && [ "${FSTYPE}" != "xfs" ]; then
        echo "Filesystem ${FSTYPE} is not supported, exit"
        exit 1
    fi
else
    echo -n "Select target device for bootloader (by default '/dev/sda'): "
    read DEV
    if [ "${DEV}" == "" ]; then
        DEV="/dev/sda"
    fi

    if ! [ -e ${DEV} ]; then
        echo "${DEV} is not exists, exit"
        exit 1
    fi

    if ! [ -b ${DEV} ]; then
        echo "${DEV} is not a block device, exit"
        exit 1
    fi
    
    echo -n "Select device partition for install (by default '/dev/sda1'): "
    read DEVPART
    if [ "${DEVPART}" == "" ]; then
        echo "Partition for install is empty, exit"
        exit 1
    fi
fi

echo -n "Input hostname (by default 'gentoo-server'): "
read HOSTNAME
if [ "${HOSTNAME}" == "" ]; then
    HOSTNAME="gentoo-server"
fi

echo -n "Would you like to use oarproxy (Signatec intranet) as http proxy? [yes/no] (by default 'yes'): "
read USE_OARPROXY
if [ "${USE_OARPROXY}" == "" ] || [ "${USE_OARPROXY}" == "y" ] || [ "${USE_OARPROXY}" == "yes" ]; then
    USE_OARPROXY="yes"
else
    USE_OARPROXY="no"
fi

# Confirmation
if [ "${INSTALLMODE}" == "device" ]; then
    echo "Selected device:     ${DEV}"
    echo "Selected filesystem: ${FSTYPE}"
else
    echo "Selected device for bootloader: ${DEV}"
    echo "Selected partition for install: ${DEVPART}"
fi
echo "Selected hostname:   ${HOSTNAME}"
echo "Using oarproxy:      ${USE_OARPROXY}"
echo -n "Press any key for continue or Ctrl+C for abort"
read USERREPLY

# TODO: setup http proxy
# TODO: add verification of an existing hard drives list (lsblk)
# TODO: add possibility for install grub not only into hd0

################################################

# example for static ip:
#cat /etc/conf.d/net

#config_eth0="192.168.18.28/24"
#routes_eth0="default via 192.168.18.254"
#dns_servers_eth0="192.168.0.1 192.168.0.100"
################################################

TARGET_MOUNT_POINT="/mnt/gentoo"

if [ "${INSTALLMODE}" == "device" ]; then
    BIOSGRUB_PARTNO=1
    SYS_PARTNO=2
    DEVPART="${DEV}${SYS_PARTNO}"

    echo "Cleaning the GPT and MBR data structures"
    # Zap (destroy) the GPT and MBR data structures
    sgdisk -Z ${DEV}
    # Clear out all partition data
    sgdisk -o ${DEV}

    echo "Creating new GPT partition"
    BEGINSECTOR=`sgdisk -F ${DEV}`
    ENDSECTOR=`sgdisk -E ${DEV}`
    #MIDDLESECTOR=$(($BEGINSECTOR + 2013))
    MIDDLESECTOR=4096
    sgdisk -n${SYS_PARTNO}:${MIDDLESECTOR}:${ENDSECTOR} ${DEV} -t${SYS_PARTNO}:8300
    # For grub2 with GPT needs special boot partition
    ENDSECTOR=`sgdisk -E ${DEV}`
    sgdisk -n${BIOSGRUB_PARTNO}:${BEGINSECTOR}:${ENDSECTOR} ${DEV} -t${BIOSGRUB_PARTNO}:ef02

    echo "Creating filesystem"
    if [ "${FSTYPE}" == "reiserfs" ]; then
        mkfs.reiserfs -q ${DEVPART}
    elif [ "${FSTYPE}" == "xfs" ]; then
        mkfs.xfs -f ${DEVPART}
    elif [ "${FSTYPE}" == "ext4" ]; then
        mkfs.ext4 ${DEVPART}
    fi
    
    mount ${DEVPART} ${TARGET_MOUNT_POINT}
else

    mount ${DEVPART} ${TARGET_MOUNT_POINT}
    MOUNTLINE=`cat /proc/mounts |grep ${DEVPART}|grep ${TARGET_MOUNT_POINT}`
    FSTYPE=( $MOUNTLINE )
    FSTYPE=${FSTYPE[2]}
    
    if [ "${FSTYPE}" != "reiserfs" ] && [ "${FSTYPE}" != "ext4" ] && [ "${FSTYPE}" != "xfs" ]; then
        echo "Filesystem ${FSTYPE} is not supported, exit"
        umount ${TARGET_MOUNT_POINT}
        exit 1
    fi
fi

echo "Copying system, please wait ..."
pv /mnt/livecd/files/gentoo-server.tar.xz | tar -xvJpf- -C ${TARGET_MOUNT_POINT} 1>/dev/null

HOSTNAME_TEXT="# Set to the hostname of this machine\n"
HOSTNAME_TEXT+="hostname=\"${HOSTNAME}\"\n"
echo -e ${HOSTNAME_TEXT} > ${TARGET_MOUNT_POINT}/etc/conf.d/hostname

if [ "${USE_OARPROXY}" != "no" ]; then
    PROXY_TEXT=""
    PROXY_TEXT+="http_proxy=http://oarproxy:3128\n"
    PROXY_TEXT+="https_proxy=http://oarproxy:3128\n"
    PROXY_TEXT+="no_proxy=localhost,127.0.0.1,az,gl,kb,sharepoint2,redmine,jenkins,oarproxy,vcs\n"

    echo -e ${PROXY_TEXT} > ${TARGET_MOUNT_POINT}/etc/env.d/99local
fi

DISK_UUID=`blkid -s UUID -o value ${DEVPART}`

echo "Fixing /etc/fstab"
FS_MOUNT_DEV="/dev/disk/by-uuid/${DISK_UUID}"

FS_MOUNT_OPTS="defaults,relatime,nodiratime"
if [ "${FSTYPE}" == "reiserfs" ]; then
    FS_MOUNT_OPTS+=",notail"
elif [ "${FSTYPE}" == "xfs" ]; then
    FS_MOUNT_OPTS+=",nobarrier,logbufs=8,logbsize=256k,osyncisdsync"
elif [ "${FSTYPE}" == "ext4" ]; then
    FS_MOUNT_OPTS+=",nobarrier,async"
fi

FSTAB_TEXT=""
FSTAB_TEXT+="${FS_MOUNT_DEV}   /           ${FSTYPE}       ${FS_MOUNT_OPTS}      0 1\n"
FSTAB_TEXT+="none              /proc       proc            defaults              0 0\n"
FSTAB_TEXT+="shm               /dev/shm    tmpfs           nodev,nosuid,noexec   0 0\n"
FSTAB_TEXT+="\n"

echo -e ${FSTAB_TEXT} > ${TARGET_MOUNT_POINT}/etc/fstab

chroot ${TARGET_MOUNT_POINT} /bin/bash --login <<CHROOTED
    env-update && source /etc/profile
    [ -e /lib64/rc/cache ] || mkdir -p /lib64/rc/cache
CHROOTED

echo "Installing GRUB"

grub2-install --boot-directory=${TARGET_MOUNT_POINT}/boot ${DEV}
mount -t proc proc    ${TARGET_MOUNT_POINT}/proc
mount --rbind /sys    ${TARGET_MOUNT_POINT}/sys
mount --rbind /dev    ${TARGET_MOUNT_POINT}/dev
chroot ${TARGET_MOUNT_POINT} /bin/bash --login <<CHROOTED
    grub2-mkconfig -o /boot/grub/grub.cfg
CHROOTED
umount -l ${TARGET_MOUNT_POINT}/sys
umount -l ${TARGET_MOUNT_POINT}/dev{/shm,/pts,}
umount -l ${TARGET_MOUNT_POINT}/proc

################################

# GRUB_PARTNO=`expr ${SYS_PARTNO} - 1`
# 
# LINUX_VER_PREFIX="linux-"
# LINUX_VER_PREFIX_LEN=${#LINUX_VER_PREFIX}
# LINUX_VER_NAME="${TARGET_MOUNT_POINT}/usr/src/linux"
# LINUX_VER_NAME=`realpath ${LINUX_VER_NAME}`
# LINUX_VER_NAME=`basename ${LINUX_VER_NAME}`
# LINUX_VER_NAME=${LINUX_VER_NAME:LINUX_VER_PREFIX_LEN}
# 
# GRUBCONF_TEXT="\n"
# GRUBCONF_TEXT+="default 0\n"
# GRUBCONF_TEXT+="timeout 3\n"
# GRUBCONF_TEXT+="\n"
# GRUBCONF_TEXT+="# Nice, fat splash-image to spice things up :)\n"
# GRUBCONF_TEXT+="# Comment out if you don't have a graphics card installed\n"
# GRUBCONF_TEXT+="splashimage=(hd0,${GRUB_PARTNO})/boot/grub/splash.xpm.gz\n"
# GRUBCONF_TEXT+="\n\n"
# GRUBCONF_TEXT+="title=Gentoo Linux ${LINUX_VER_NAME}\n"
# GRUBCONF_TEXT+="root (hd0,${GRUB_PARTNO})\n"
# GRUBCONF_TEXT+="kernel /boot/kernel-genkernel-x86_64-${LINUX_VER_NAME}"
# GRUBCONF_TEXT+=" root=/dev/ram0 init=/linuxrc ramdisk=8192 real_root=UUID=${DISK_UUID}"
# # The most reliable way of disabling the new predictable network interface names
# GRUBCONF_TEXT+=" net.ifnames=0"
# 
# GRUBCONF_TEXT+=" vga=791 initrd udev dolvm dodmraid doscsi"
# 
# # for HP SmartArray
# #GRUBCONF_TEXT+=" cciss.cciss_allow_any=1"
# GRUBCONF_TEXT+="\n"
# GRUBCONF_TEXT+="initrd /boot/initramfs-genkernel-x86_64-${LINUX_VER_NAME}\n"
# GRUBCONF_TEXT+="\n"
# echo -e ${GRUBCONF_TEXT} > ${TARGET_MOUNT_POINT}/boot/grub/grub.conf
# 
# grub-install --recheck --no-floppy --root-directory=${TARGET_MOUNT_POINT}/boot ${DEV}
# 
# #TODO: add check target device is /dev/vdX and create for this case map file
# 
# # Sometimes grub can not map the selected device (for virtio with KVM for example)
# GRUB_DEVICE_MAPFILE=${TARGET_MOUNT_POINT}/boot/grub/device.map
# GRUB_DEVICE_FOUND=`grep ${DEV} ${GRUB_DEVICE_MAPFILE} | wc -l`
# if [ "${GRUB_DEVICE_FOUND}" == "0" ]; then
#     # TODO: check if hd0 already exists
#     echo "(hd0)   ${DEV}" >> ${GRUB_DEVICE_MAPFILE}
# fi
# grub-install --no-floppy --root-directory=${TARGET_MOUNT_POINT}/boot ${DEV}

umount ${TARGET_MOUNT_POINT}

echo "Installation done. Now you must reboot the OS. Type 'reboot' for this."
