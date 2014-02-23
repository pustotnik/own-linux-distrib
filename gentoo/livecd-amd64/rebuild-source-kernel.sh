#!/bin/bash

# detect current directory
BASEDIR=`dirname $0`
BASEDIR=`(cd "$BASEDIR"; pwd)`

. ${BASEDIR}/common

if [ -e ${SOURCE} ] && ! [ -d ${SOURCE} ]; then
    echo "${SOURCE} is exists but not directory, exit"
    exit 1
fi

mkdir -p ${SOURCE}${INSOURCE_PREPARED}
cp -a ${PREPARED}/* ${SOURCE}${INSOURCE_PREPARED}/

# fix permissions
chown -R root:root       ${SOURCE}${INSOURCE_PREPARED}
chmod -R u=rwX,g=rX,o=rX ${SOURCE}${INSOURCE_PREPARED}

mount_for_source
    
chroot ${SOURCE} /bin/bash --login <<CHROOTED
env-update && source /etc/profile
cat /proc/mounts > /etc/mtab
CHROOTED

chroot ${SOURCE} /bin/bash -i -c "genkernel all --menuconfig --no-splash --kernel-config=${INSOURCE_PREPARED}/kernel-config"

chroot ${SOURCE} /bin/bash --login <<CHROOTED
#module-rebuild populate
#module-rebuild rebuild
emerge -a n @module-rebuild

rm -f /boot/initrd
rm -f /boot/vmlinuz
mv /boot/initramfs-genkernel-* /boot/initrd
mv /boot/kernel-genkernel-* /boot/vmlinuz
(
    cd /usr/src/linux 
    make clean
)

rm -fr ${INSOURCE_PREPARED}
    
echo "updatedb ..."
updatedb

CHROOTED
    
umount_for_source

cp -a ${PREPARED}/kernel-config ${PREPARED}/kernel-config.bak
cat ${SOURCE}/etc/kernels/kernel-config-x86_64* > ${PREPARED}/kernel-config

# need copy modules also
#if [ -e ${TARGET}/boot ]; then 
#    cp -a ${SOURCE}/boot/initrd      ${TARGET}/boot/initrd
#    cp -a ${SOURCE}/boot/vmlinuz     ${TARGET}/boot/vmlinuz
#    cp -a ${SOURCE}/boot/System.map* ${TARGET}/boot/
#fi
#
#if [ -e ${TARGET_SOURCE} ]; then 
#    cp -a ${SOURCE}/boot/initrd      ${TARGET_SOURCE}/boot/initrd
#    cp -a ${SOURCE}/boot/vmlinuz     ${TARGET_SOURCE}/boot/vmlinuz
#    cp -a ${SOURCE}/boot/System.map* ${TARGET_SOURCE}/boot/
#fi

echo " Work done."
