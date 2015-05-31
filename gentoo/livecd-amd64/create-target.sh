#!/bin/bash

# detect current directory
BASEDIR=`dirname $0`
BASEDIR=`(cd "$BASEDIR"; pwd)`

. ${BASEDIR}/common

if [ "${TARGET}" == "" ] || [ "${TARGET_SOURCE}" == "" ]; then
    echo "TARGET or TARGET_SOURCE is empty, exit"
    exit 1
fi

if [ -e ${TARGET} ] && ! [ -d ${TARGET} ]; then
    echo "${TARGET} is exists but not directory, exit"
    exit 1
fi

echo " ==== Creating of target livecd files ..."

[ -e ${TARGET} ] || mkdir -p ${TARGET}

if ! [ -e ${TARGET}/boot ]; then 
    echo "Copying boot ..."
    cp -a ${SOURCE}/boot ${TARGET}
    
    rm ${TARGET}/boot/grub/menu.lst
    cp -a ${TARGET}/boot/grub/grub.conf ${TARGET}/boot/grub/menu.lst
fi

if ! [ -e ${TARGET_SOURCE} ]; then 

    mkdir -p ${TARGET_SOURCE}

    echo "Copying source (as hard links), please wait ..."
    RSYNC="rsync --delete-after --archive --hard-links"
    if [ ${PV_PATH} ]; then
        FILES_COUNT=$(find ${SOURCE} | wc -l)
        RSYNC="${RSYNC} -v"
        ${RSYNC} ${SOURCE}/ ${TARGET_SOURCE} | pv -ptel -s "${FILES_COUNT}" 1>/dev/null
    else        
        ${RSYNC} ${SOURCE}/ ${TARGET_SOURCE}
    fi
    
    rm ${TARGET_SOURCE}/boot/grub/menu.lst    
    cp -a ${TARGET_SOURCE}/boot/grub/grub.conf ${TARGET_SOURCE}/boot/grub/menu.lst

    echo "Extra cleaning ..."
        
    for i in `cat ${SOURCE}/root/USELESSFILELIST`
    do
        if [ -f ${TARGET_SOURCE}${i} ]; then 
            rm ${TARGET_SOURCE}${i} 
        fi 
        if [ -L ${TARGET_SOURCE}${i} ]; then 
            rm ${TARGET_SOURCE}${i} 
        fi 
        if [ -d ${TARGET_SOURCE}${i} ]; then 
            rmdir ${TARGET_SOURCE}${i} 
        fi 
    done

    rm -fr ${TARGET_SOURCE}/var/tmp/*
    rm -fr ${TARGET_SOURCE}/var/cache/*
    rm -fr ${TARGET_SOURCE}/var/log/*
    rm -fr ${TARGET_SOURCE}/usr/portage
    rm -fr ${TARGET_SOURCE}/etc/portage
    rm -fr ${TARGET_SOURCE}/usr/src
    rm -fr ${TARGET_SOURCE}/usr/share/doc
    rm -fr ${TARGET_SOURCE}/usr/include/*
    rm -fr ${TARGET_SOURCE}/root/*
    rm -fr ${TARGET_SOURCE}/tmp/*

    find ${TARGET_SOURCE}/usr/lib/ -name "*.a" -exec rm -f {} \;
    find ${TARGET_SOURCE}/ -xdev -name ".keep" -exec rm -f {} \;
    
    # this need to remove unneeded warnings about updates of config files
    find ${TARGET_SOURCE}/etc -name "._cfg*" -exec rm -f {} \;
fi

if [ "${CREATE_SERVER}" != "" ]; then
    echo "Preparing of server image"
    
    if [ "${SOURCE_SERVERFILES}" == "" ] || [ "${TARGET_SERVER_IMAGE}" == "" ]; then
        echo "SOURCE_SERVERFILES or TARGET_SERVER_IMAGE is empty, exit"
        exit 1
    fi

    if ! [ -e ${SOURCE_SERVERFILES} ]; then
        echo "${SOURCE_SERVERFILES} is not exists, exit"
        exit 1
    fi

    if [ -e ${SOURCE_SERVERFILES} ] && ! [ -d ${SOURCE_SERVERFILES} ]; then
        echo "${SOURCE_SERVERFILES} is exists but not directory, exit"
        exit 1
    fi
    
    [ -e ${TARGET_SERVER_IMAGE_DIR} ] || mkdir -p ${TARGET_SERVER_IMAGE_DIR}
    
    if ! [ -e ${TARGET_SERVER_IMAGE} ]; then        

        echo "Compressing files for the server image, please wait ..."
        rm -f ${TARGET_SERVER_IMAGE}
        cd "${SOURCE_SERVERFILES}"
        if [ ${PV_PATH} ]; then
            (tar cf - "." \
                | pv -pte -s $(du -sb ${SOURCE_SERVERFILES} | awk '{print $1}') \
                | xz -f > ${TARGET_SERVER_IMAGE} )
        else
            tar cf - "." | xz -f > ${TARGET_SERVER_IMAGE}
        fi
    fi
    
    cp ${PREPARED}/install-system.sh ${TARGET_SERVER_IMAGE_DIR}/install-system.sh    
    chown root:root ${TARGET_SERVER_IMAGE_DIR}/install-system.sh
    chmod u=rwx,g=rwx,o-rwx ${TARGET_SERVER_IMAGE_DIR}/install-system.sh
    RELATIVE_SCRIPT_PATH=`python -c "import os.path; print os.path.relpath(\
        \"${TARGET_SERVER_IMAGE_DIR}\", \"${TARGET_SOURCE}/usr/bin\")"`    
    ln -fs ${RELATIVE_SCRIPT_PATH}/install-system.sh ${TARGET_SOURCE}/usr/bin/install-system 
else
    rm -fr ${TARGET_SERVER_IMAGE_DIR}
    rm -f  ${TARGET_SOURCE}/usr/bin/install-system 
fi

# reset bash history
echo "" > ${TARGET_SOURCE}/root/.bash_history

echo "Making squashfs image ..."
rm -f ${TARGET}/livecd.squashfs
mksquashfs ${TARGET_SOURCE} ${TARGET}/livecd.squashfs

# Next, create the required empty livecd file. This file must be on livecd root, 
# because the init script in initramfs uses this file to identify if the CD is mounted or not. 
touch ${TARGET}/livecd

echo " ==== Creating of target livecd files is done."
