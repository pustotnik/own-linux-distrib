#!/bin/bash

# detect current directory
BASEDIR=`dirname $0`
BASEDIR=`(cd "$BASEDIR"; pwd)`

. ${BASEDIR}/common

if [ -e ${TARGET} ] && ! [ -d ${TARGET} ]; then
    echo "${TARGET} is exists but not directory, exit"
    exit 1
fi

if [ -e ${TARGET} ]; then
    echo "${TARGET} is exists already, exit"
    exit 0
fi

echo " ==== Building system ..."

mkdir -p ${TARGET}

cd ${TARGET}

if ! [ -f ${BASEDIR}/stage3-*.tar.bz2 ]; then
    wget -c -P ${BASEDIR} -r --level=1 -nd -A stage3-amd64*.tar.bz2 -R *nomultilib* http://mirror.yandex.ru/gentoo-distfiles/releases/amd64/current-stage3/
fi
echo "Extracting stage3 files ..."
if [ ${PV_PATH} ]; then
    pv ${BASEDIR}/stage3-*.tar.bz2 | tar -xvjpf - 1>/dev/null        
else
    tar -xvjpf ${BASEDIR}/stage3-*.tar.bz2
fi

if ! [ -f ${BASEDIR}/portage-latest.tar.xz ]; then
    wget -c -P ${BASEDIR} http://mirror.yandex.ru/gentoo-distfiles/snapshots/portage-latest.tar.xz
fi    
echo "Extracting portage files ..."
if [ ${PV_PATH} ]; then
    pv ${BASEDIR}/portage-latest.tar.xz | tar -xvJpf- -C usr 1>/dev/null
else
    tar -xvJpf ${BASEDIR}/portage-latest.tar.xz -C usr
fi

#rm -f ${LIVECD}/stage3-*.tar.bz2
#rm -f ${LIVECD}/portage-latest.tar.xz

[ -e proc ]        || mkdir proc
[ -e dev ]         || mkdir dev
[ -e sys ]         || mkdir sys
[ -e usr/portage ] || mkdir usr/portage

mkdir -p ${TARGET}${INSOURCE_PREPARED}
cp -a ${PREPARED}/* ${TARGET}${INSOURCE_PREPARED}/

# fix permissions
chown -R root:root       ${TARGET}${INSOURCE_PREPARED}
chmod -R u=rwX,g=rX,o=rX ${TARGET}${INSOURCE_PREPARED}

cp -a /etc/resolv.conf  ${TARGET}/etc/resolv.conf

mount_for_source

chroot ${TARGET} /bin/bash --login <<CHROOTED   
env-update && source /etc/profile 
# set the root password for the new environment in case of problems later   
echo "root:1q2w3e" | chpasswd
eselect profile set 1
eselect news read all

chmod a+r /etc/resolv.conf

emerge -a n dev-lang/python:2.7
eselect python set 1
python-updater -- -a n

emerge -a n dev-util/ccache

cp -a ${INSOURCE_PREPARED}/locale.gen  /etc/locale.gen
cp -a ${INSOURCE_PREPARED}/make.conf   /etc/portage/make.conf
cp -a ${INSOURCE_PREPARED}/package.use /etc/portage/package.use

# see http://forums.gentoo.org/viewtopic-t-297935.html
FEATURES="-sandbox" USE="multilib" emerge -a n gcc portage

emerge -a n sys-kernel/gentoo-sources

emerge -a n -uDN world
emerge -a n gentoolkit
revdep-rebuild -- -a n

#emerge -a n -1 gcc
#emerge -a n -1 glibc
#emerge -a n -e world --exclude glibc --exclude gcc

emerge -a n genkernel dmraid logrotate syslog-ng monit app-admin/mcelog            \
    eix htop vim sudo mlocate app-arch/dpkg app-arch/lha app-arch/lzip             \
    app-arch/p7zip app-arch/rar app-misc/mc app-misc/screen net-fs/nfs-utils       \
    net-fs/samba  dev-libs/boost imagemagick layman app-admin/sysstat              \
    dev-util/intel-ocl-sdk dev-util/strace dev-util/valgrind dev-vcs/git           \
    dev-vcs/mercurial dev-vcs/subversion net-analyzer/tcpreplay net-dns/bind-tools \
    net-dialup/ppp net-analyzer/netcat6 net-analyzer/tcpdump net-libs/libpcap      \
    net-analyzer/traceroute net-misc/dhcpcd net-misc/netkit-telnetd                \
    net-misc/whois net-misc/ntp sys-block/parted sys-fs/reiserfsprogs              \
    sys-fs/sshfs-fuse sys-fs/xfsprogs sys-apps/hdparm sys-apps/iproute2            \
    sys-kernel/module-rebuild sys-apps/pv ddrescue gptfdisk lm_sensors             \
    sys-apps/lshw smartmontools sys-devel/gdb lsof vixie-cron lynx ntop            \
    dmidecode dstat grub ethtool nload pciutils

(
    echo "" > /etc/udev/rules.d/80-net-name-slot.rules
    cd /etc/init.d
    ln -s net.lo net.eth0
    rc-update add net.eth0 default
)

# this need to remove unneeded updates of config files
find /etc -name "._cfg*" -exec rm -f {} \;

cp -a ${INSOURCE_PREPARED}/localtime     /etc/localtime
cp -a ${INSOURCE_PREPARED}/timezone      /etc/timezone
cp -a ${INSOURCE_PREPARED}/hwclock       /etc/conf.d/hwclock
cp -a ${INSOURCE_PREPARED}/hostname      /etc/conf.d/hostname
cp -a ${INSOURCE_PREPARED}/rc.conf       /etc/rc.conf
cp -a ${INSOURCE_PREPARED}/02locale      /etc/env.d/02locale
cp -a ${INSOURCE_PREPARED}/keymaps       /etc/conf.d/keymaps
cp -a ${INSOURCE_PREPARED}/consolefont   /etc/conf.d/consolefont
cp -a ${INSOURCE_PREPARED}/issue         /etc/issue

chmod u+w /etc/sudoers
rm -f /etc/sudoers
cp -a ${INSOURCE_PREPARED}/sudoers       /etc/sudoers
chmod u=r,g=r,o= /etc/sudoers

cp -a ${INSOURCE_PREPARED}/locale.gen /etc/locale.gen
locale-gen

env-update && source /etc/profile

cat /proc/mounts > /etc/mtab

#genkernel all --no-mountboot --all-ramdisk-modules --disklabel --kernel-config=${INSOURCE_PREPARED}/kernel-config
genkernel all --no-mountboot --disklabel --kernel-config=${INSOURCE_PREPARED}/kernel-config
module-rebuild populate
module-rebuild rebuild

(
    cd /usr/src/linux 
    make clean
)

rm -fr ${INSOURCE_PREPARED}
CCACHE_DIR='/var/tmp/ccache' ccache -C

chmod +x /etc/portage/postsync.d/q-reinitialize
rc-update add syslog-ng default
rc-update add vixie-cron default
rc-update add sshd default

# setup ntp updates
echo '#!/bin/bash'                            >  /etc/cron.hourly/ntpupdate
echo 'ntpdate pool.ntp.org  2>&1 > /dev/null' >> /etc/cron.hourly/ntpupdate
chown root:root                                  /etc/cron.hourly/ntpupdate
chmod u=rwx,g=rx,o=rx                            /etc/cron.hourly/ntpupdate

(
    cd /etc
    ln -s /etc/portage/make.conf make.conf
)

makewhatis -u
eix-update

echo "updatedb ..."
updatedb

    
CHROOTED
    
umount_for_source

# reset bash history
echo "" > ${TARGET}/root/.bash_history

echo " ==== Work done."
