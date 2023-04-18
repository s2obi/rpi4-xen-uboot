#!/bin/bash -eux

# SPDX-License-Identifier: MIT

# Copyright (c) 2019, DornerWorks, Ltd.
# Author: Stewart Hildebrand

# Copyright (c) 2020 MERA                                                                                               
# Author: Leonid Lazarev

WRKDIR=$(pwd)/

#name for output
IMGFILE=$1
MNTRAMDISK=$2
ARCH=${3:-arm64}
DNS_SERVER=${4,-""}
PROXY=${5:-""}

echo $PROXY
sudo apt install qemu-user-static

# Download Ubuntu Base file system (https://wiki.ubuntu.com/Base)
ROOTFSURL=https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/
ROOTFS=ubuntu-base-22.04.2-base-${ARCH}.tar.gz
if [ ! -s ${ROOTFS} ]; then
    curl -OLf ${ROOTFSURL}${ROOTFS}
fi

MNTROOTFS=${MNTRAMDISK}qemu-${ARCH}-rootfs/

if [ -s ${IMGFILE} ]; then
    ROOTFS=${IMGFILE}
fi

IMGFILE=${MNTRAMDISK}${IMGFILE}

unmountstuff () {
  sudo umount ${MNTROOTFS}proc || true
  sudo umount ${MNTROOTFS}dev/pts || true
  sudo umount ${MNTROOTFS}dev || true
  sudo umount ${MNTROOTFS}sys || true
  sudo umount ${MNTROOTFS}tmp || true
}

mountstuff () {
  sudo mkdir -p ${MNTROOTFS}
  sudo mount -o bind /proc ${MNTROOTFS}proc
  sudo mount -o bind /dev ${MNTROOTFS}dev
  sudo mount -o bind /dev/pts ${MNTROOTFS}dev/pts
  sudo mount -o bind /sys ${MNTROOTFS}sys
  sudo mount -o bind /tmp ${MNTROOTFS}tmp
}

finish () {
  cd ${WRKDIR}
  sudo sync
  unmountstuff
  sudo tar -czf ${IMGFILE} -C ${MNTROOTFS} $(ls ${MNTROOTFS}) || true
  sudo chown $USER:$USER ${IMGFILE} || true
  sudo rm -rf ${MNTROOTFS} || true
  mv ${IMGFILE} . || true
  sudo umount ${MNTRAMDISK} || true
  sudo rmdir ${MNTRAMDISK} || true
}

trap finish EXIT


sudo mkdir -p ${MNTRAMDISK}
sudo mount -t tmpfs -o size=3g tmpfs ${MNTRAMDISK}

sudo mkdir -p ${MNTROOTFS}
sudo tar -C ${MNTROOTFS} -xf ${ROOTFS}

mountstuff

if [ "${ARCH}" == "arm64" ]; then
    sudo cp $(which qemu-aarch64-static) ${MNTROOTFS}usr/bin/
elif [ "${ARCH}" == "armhf" ]; then
    sudo cp `which qemu-arm-static` ${MNTROOTFS}usr/bin/
fi

# /etc/resolv.conf is required for internet connectivity in chroot. It will get overwritten by dhcp, so don't get too attached to it.
if [ ! -z ${DNS_SERVER} ]; then
    sudo chroot ${MNTROOTFS} bash -c 'echo "nameserver '$DNS_SERVER'" > /etc/resolv.conf'
fi

sudo sed -i -e "s/# deb /deb /" ${MNTROOTFS}etc/apt/sources.list
echo $PROXY
if [ ! -z ${PROXY} ]; then
    sudo chroot ${MNTROOTFS} bash -c 'echo "Acquire::http::Proxy \"http://'$PROXY'\""; > etc/apt/apt.conf'
    sudo cat ${MNTROOTFS}etc/apt/apt.conf
fi

sudo  chroot  ${MNTROOTFS} apt-get update

# Install the dialog package and others first to squelch some warnings
sudo chroot ${MNTROOTFS} apt-get -y install dialog apt-utils
sudo chroot ${MNTROOTFS} apt-get -y upgrade
sudo chroot ${MNTROOTFS} apt-get -y install systemd systemd-sysv sysvinit-utils sudo udev rsyslog kmod util-linux sed netbase dnsutils ifupdown isc-dhcp-client isc-dhcp-common less nano vim net-tools iproute2 iputils-ping libnss-mdns iw software-properties-common ethtool dmsetup hostname iptables logrotate lsb-base lsb-release plymouth psmisc tar tcpd libsystemd-dev symlinks uuid-dev libc6-dev libncurses-dev libglib2.0-dev build-essential bridge-utils zlib1g-dev patch libpixman-1-dev libyajl-dev libfdt-dev libaio-dev git libusb-1.0-0-dev libpulse-dev libcapstone-dev libnl-route-3-dev openssh-sftp-server xen-doc xen-tools xen-utils-4.16 libxen-dev
sudo chroot ${MNTROOTFS} apt-get clean
sudo cp regenerate_ssh_host_keys.service ${MNTROOTFS}etc/systemd/system
sudo chroot ${MNTROOTFS} systemctl enable regenerate_ssh_host_keys.service

if [ "${ARCH}" == "amd64" ]; then
    sudo chroot ${MNTROOTFS} apt-get -y install bin86 bcc liblzma-dev ocaml python python-dev gettext acpica-tools wget ftp build-essential gcc-multilib
fi
