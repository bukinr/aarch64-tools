#!/bin/sh
#-
# Copyright (c) 2015 Ruslan Bukin <br@bsdpad.com>
# All rights reserved.
#
# This software was developed by the University of Cambridge Computer
# Laboratory as part of the CTSRD Project, with support from the UK Higher
# Education Innovation Fund (HEIF).
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

export TARGET=arm64

#
# Predefined path to workspace
#
export WORKSPACE=$(realpath $HOME)/arm64-workspace
export MAKEOBJDIRPREFIX=$WORKSPACE/obj/
export ROOTFS=$WORKSPACE/rootfs

#
# Sanity checks
#
if [ "$USER" == "root" ]; then
	echo "Error: Can't run under root"
	exit 1
fi

if [ "$(uname -s)" != "FreeBSD" ]; then
	echo "Error: Can run on FreeBSD only"
	exit 1
fi

#
# Get path to SRC tree
#
if [ -z "$1" ]; then
	echo "Usage: $0 path-to-svn-src-tree"
	exit 1
fi

if [ ! -d "$1" ]; then
	echo "Error: Provided path ($1) is not a directory"
	exit 1
fi

export SRC=$(realpath $1)
export MAKESYSPATH=$SRC/share/mk
if [ ! -d "$MAKESYSPATH" ]; then
	echo "Error: Can't find svn src tree"
	exit 1
fi

#
# Create dirs
#
mkdir -p $ROOTFS $MAKEOBJDIRPREFIX

#
# Number of CPU for parallel build
#
export NCPU=$(sysctl -n hw.ncpu)

#
# Build FreeBSD
#
cd $SRC && \
make -j $NCPU buildworld && \
make -j $NCPU buildkernel KERNCONF=GENERIC -DNO_MODULES || exit $?

#
# Install FreeBSD
#
cd $SRC && \
make -DNO_ROOT -DWITHOUT_TESTS DESTDIR=$ROOTFS installworld && \
make -DNO_ROOT -DWITHOUT_TESTS DESTDIR=$ROOTFS distribution && \
make -DNO_ROOT -DWITHOUT_TESTS -DNO_MODULES DESTDIR=$ROOTFS installkernel KERNCONF=GENERIC || exit $?

#
# Setup rootfs for QEMU
#
echo '/dev/vtbd0s2 / ufs rw,noatime 1 1' > $ROOTFS/etc/fstab
echo './etc/fstab type=file uname=root gname=wheel mode=644' >> $ROOTFS/METALOG

#
# Rootfs image. 1G size, 10k free inodes
#
cd $ROOTFS && \
/usr/sbin/makefs -f 10000 -s 1073741824 -D rootfs.img METALOG || exit $?

#
# Final ARM64 image. Notice: you may have to update your mkimg(1) from svn src head.
#
echo "Using $WORKSPACE/obj/arm64.aarch64/$SRC/sys/boot/efi/boot1/boot1.efifat"
/usr/bin/mkimg -s mbr -p efi:=$WORKSPACE/obj/arm64.aarch64/$SRC/sys/boot/efi/boot1/boot1.efifat -p freebsd:=rootfs.img -o disk.img || exit $?

echo "Disk image ready: $ROOTFS/disk.img"
