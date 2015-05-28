#!/bin/bash

# detect current directory
BASEDIR=`dirname $0`
BASEDIR=`(cd "$BASEDIR"; pwd)`

. ${BASEDIR}/common

if [ -e ${SOURCE} ] && ! [ -d ${SOURCE} ]; then
    echo "${SOURCE} is exists but not directory, exit"
    exit 1
fi

echo " ==== Creating of source livecd files ..."

if ! [ -e ${SOURCE} ]; then
    mkdir -p ${SOURCE}
    
    cd ${SOURCE} 
    
    if ! [ -f ${LIVECD}/stage3-*.tar.bz2 ]; then
        wget -c -P ${LIVECD} -r --level=1 -nd -A stage3-amd64*.tar.bz2 -R *nomultilib* http://mirror.yandex.ru/gentoo-distfiles/releases/amd64/autobuilds/current-stage3-amd64/
    fi
    chmod a+rw ${LIVECD}/stage3-*.tar.bz2
    
    echo "Extracting stage3 files ..."
    if [ ${PV_PATH} ]; then
        pv ${LIVECD}/stage3-*.tar.bz2 | tar -xvjpf - 1>/dev/null        
    else
        tar -xvjpf ${LIVECD}/stage3-*.tar.bz2
    fi
    
    if ! [ -f ${LIVECD}/portage-latest.tar.xz ]; then
        wget -c -P ${LIVECD} http://mirror.yandex.ru/gentoo-distfiles/snapshots/portage-latest.tar.xz
    fi    
    chmod a+rw ${LIVECD}/portage-latest.tar.xz
    
    echo "Extracting portage files ..."
    if [ ${PV_PATH} ]; then
        pv ${LIVECD}/portage-latest.tar.xz | tar -xvJpf- -C usr 1>/dev/null
    else
        tar -xvJpf ${LIVECD}/portage-latest.tar.xz -C usr
    fi
    
    #rm -f ${LIVECD}/stage3-*.tar.bz2
    #rm -f ${LIVECD}/portage-latest.tar.xz
    
    [ -e proc ]        || mkdir proc
    [ -e dev ]         || mkdir dev
    [ -e sys ]         || mkdir sys
    [ -e usr/portage ] || mkdir usr/portage
    
    mkdir -p ${SOURCE}${INSOURCE_PREPARED}
    cp -a ${PREPARED}/* ${SOURCE}${INSOURCE_PREPARED}/
    
    # fix permissions
    chown -R root:root       ${SOURCE}${INSOURCE_PREPARED}
    chmod -R u=rwX,g=rX,o=rX ${SOURCE}${INSOURCE_PREPARED}
    
    cp -a /etc/resolv.conf                        ${SOURCE}/etc/resolv.conf
    cp -a ${SOURCE}${INSOURCE_PREPARED}/02locale  ${SOURCE}/etc/env.d/02locale
    
    mount_for_source
    
    chroot ${SOURCE} /bin/bash --login <<CHROOTED   
    
    source /etc/profile 
    
    set -ex
    
    # set the root password for the new environment in case of problems later   
    echo "root:1q2w3e" | chpasswd
    eselect profile set 1
    eselect news read all
    
    chmod a+r /etc/resolv.conf
    
    [ -e /etc/portage/repos.conf ] || mkdir /etc/portage/repos.conf
    
    cp -a ${INSOURCE_PREPARED}/make.conf         /etc/portage/make.conf
    cp -a ${INSOURCE_PREPARED}/package.use       /etc/portage/package.use
    cp -a ${INSOURCE_PREPARED}/repos-gentoo.conf /etc/portage/repos.conf/gentoo.conf
    cp -a ${INSOURCE_PREPARED}/fstab             /etc/fstab
    
    cp -a ${INSOURCE_PREPARED}/localtime         /etc/localtime
    cp -a ${INSOURCE_PREPARED}/hwclock           /etc/conf.d/hwclock
    cp -a ${INSOURCE_PREPARED}/hostname          /etc/conf.d/hostname
    cp -a ${INSOURCE_PREPARED}/rc.conf           /etc/rc.conf
    cp -a ${INSOURCE_PREPARED}/02locale          /etc/env.d/02locale
    cp -a ${INSOURCE_PREPARED}/99editor          /etc/env.d/99editor
    cp -a ${INSOURCE_PREPARED}/keymaps           /etc/conf.d/keymaps
    cp -a ${INSOURCE_PREPARED}/consolefont       /etc/conf.d/consolefont
    cp -a ${INSOURCE_PREPARED}/issue             /etc/issue
    cp -a ${INSOURCE_PREPARED}/inittab           /etc/inittab
    
    cp -a ${INSOURCE_PREPARED}/locale.gen        /etc/locale.gen
    locale-gen
    
    env-update && source /etc/profile
    
    emerge -a n sys-kernel/gentoo-sources
    emerge -a n -1 gcc
    emerge -a n -1 glibc
    emerge -a n -uDN system
    emerge -a n -uDN world
    #emerge -a n -e system --exclude glibc --exclude gcc
    #emerge -a n -e world --exclude glibc --exclude gcc
    
    emerge -a n memtest86+ localepurge genkernel gentoolkit livecd-tools       \
        eix htop vim sudo mlocate app-arch/dpkg app-arch/lha app-arch/lzip     \
        app-arch/rar app-misc/mc app-misc/screen net-fs/nfs-utils net-fs/samba \
        net-dialup/ppp net-analyzer/netcat6 net-analyzer/tcpdump               \
        net-analyzer/traceroute net-misc/dhcpcd net-misc/netkit-telnetd        \
        net-misc/whois net-misc/ntp sys-block/parted sys-fs/reiserfsprogs      \
        sys-fs/squashfs-tools sys-fs/sshfs-fuse sys-fs/xfsprogs                \
        sys-fs/dosfstools sys-apps/pv ddrescue gptfdisk dmidecode              \
        mdadm linux-firmware dev-vcs/bzr sys-fs/udftools
    
    emerge -a n scripts mingetty 
    
    #(
    #    echo "" > /etc/udev/rules.d/80-net-name-slot.rules
    #    cd /etc/init.d
    #    ln -s net.lo net.eth0
    #    rc-update add net.eth0 default
    #)
    
    # this need to remove unneeded updates of config files
    find /etc -name "._cfg*" -exec rm -f {} \;
    
    cat /proc/mounts > /etc/mtab
    
    genkernel all --no-splash --firmware --busybox --all-ramdisk-modules --kernel-config=${INSOURCE_PREPARED}/kernel-config
    #module-rebuild populate
    #module-rebuild rebuild
    emerge -a n @module-rebuild
    
    mv /boot/initramfs-genkernel-* /boot/initrd
    mv /boot/kernel-genkernel-* /boot/vmlinuz
    (
        cd /usr/src/linux 
        make clean
    )
    
    emerge -a n grub-static
    emerge -a n grub:2
    
    #rm /boot/grub/menu.lst
    cp -a ${INSOURCE_PREPARED}/grub.conf /boot/grub/grub.conf
    #cp -a ${INSOURCE_PREPARED}/grub.conf /boot/grub/menu.lst
    
    cp -a ${INSOURCE_PREPARED}/locale.nopurge /etc/locale.nopurge
    localepurge
    
    eselect news read all
    
    #makewhatis -u
    eix-update
    
    rm -fr ${INSOURCE_PREPARED}
    
    echo "updatedb ..."
    updatedb
    
    echo "grepping useless files for extra cleaning later ..."
    #grepping out library files for gcc
    equery files --filter=obj,conf,doc,man,info gcc | grep -v \.a$ | grep -v \.la$ | grep -v \.so\. > ~/USELESSFILELIST
    equery files --filter=obj,conf,doc,man,info portage >> ~/USELESSFILELIST
    equery files --filter=obj,conf,doc,man,info automake >> ~/USELESSFILELIST
    equery files --filter=obj,conf,doc,man,info autoconf >> ~/USELESSFILELIST
    equery files --filter=obj,conf,doc,man,info gentoolkit >> ~/USELESSFILELIST
    equery files --filter=obj,conf,doc,man,info texinfo >> ~/USELESSFILELIST
    equery files --filter=obj,conf,doc,man,info genkernel >> ~/USELESSFILELIST
    equery files --filter=obj,conf,doc,man,info flex >> ~/USELESSFILELIST
    equery files --filter=obj,conf,doc,man,info bison >> ~/USELESSFILELIST
    equery files --filter=obj,conf,doc,man,info gcc-config >> ~/USELESSFILELIST
    equery files --filter=obj,conf,doc,man,info make >> ~/USELESSFILELIST
    equery files --filter=obj,conf,doc,man,info m4 >> ~/USELESSFILELIST
    equery files --filter=obj,conf,doc,man,info patch >> ~/USELESSFILELIST
    equery files --filter=obj,conf,doc,man,info localepurge >> ~/USELESSFILELIST
    
CHROOTED
    
    umount_for_source
    
fi

echo " ==== Creation of source should be complete."
