#!/bin/bash

# detect current directory
BASEDIR=`dirname $0`
BASEDIR=`(cd "$BASEDIR"; pwd)`

. ${BASEDIR}/common

if [ -e ${TARGET} ] && ! [ -d ${TARGET} ]; then
    echo "${TARGET} is exists but not directory, exit"
    exit 1
fi

mount_for_source
    
chroot ${TARGET} /bin/bash --login
    
umount_for_source
