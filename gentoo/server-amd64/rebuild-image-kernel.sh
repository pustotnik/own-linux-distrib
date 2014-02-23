#!/bin/bash

# detect current directory
BASEDIR=`dirname $0`
BASEDIR=`(cd "$BASEDIR"; pwd)`

. ${BASEDIR}/common

if [ -e ${TARGET} ] && ! [ -d ${TARGET} ]; then
    echo "${TARGET} is exists but not directory, exit"
    exit 1
fi

mkdir -p ${TARGET}${INSOURCE_PREPARED}
cp -a ${PREPARED}/* ${TARGET}${INSOURCE_PREPARED}/

# fix permissions
chown -R root:root       ${TARGET}${INSOURCE_PREPARED}
chmod -R u=rwX,g=rX,o=rX ${TARGET}${INSOURCE_PREPARED}

mount_for_source
    
chroot ${TARGET} /bin/bash --login <<CHROOTED
env-update && source /etc/profile
cat /proc/mounts > /etc/mtab
CHROOTED

chroot ${TARGET} /bin/bash -i -c "genkernel all --menuconfig --no-splash  --no-mountboot --lvm --mdadm --disklabel --firmware --kernel-config=${INSOURCE_PREPARED}/kernel-config"
#chroot ${TARGET} /bin/bash -i -c "genkernel all --menuconfig --no-splash  --no-mountboot --disklabel --firmware --all-ramdisk-modules --kernel-config=${INSOURCE_PREPARED}/kernel-config"
#chroot ${TARGET} /bin/bash -i -c "genkernel all --no-mountboot --menuconfig --disklabel --kernel-config=${INSOURCE_PREPARED}/kernel-config"

chroot ${TARGET} /bin/bash --login <<CHROOTED
#module-rebuild populate
#module-rebuild rebuild
emerge -a n @module-rebuild

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
cat ${TARGET}/etc/kernels/kernel-config-x86_64* > ${PREPARED}/kernel-config

echo " Work done."
