#!/bin/bash

# detect current directory
BASEDIR=`dirname $0`
BASEDIR=`(cd "$BASEDIR"; pwd)`

. ${BASEDIR}/common

${BASEDIR}/create-source.sh
bash -c "CREATE_SERVER='yes' ${BASEDIR}/create-target.sh"

echo " ==== Making the ISO image ... "
rm -f ${LIVECD_ISO}
mkisofs -R -b boot/grub/stage2_eltorito -no-emul-boot -boot-load-size 4 -boot-info-table \
    -iso-level 4 -hide-rr-moved -c boot.catalog \
    -o ${LIVECD_ISO} -x ${TARGET_SOURCE} ${TARGET}
    
chmod a+r ${LIVECD_ISO}

echo " ==== The ISO image is done."
