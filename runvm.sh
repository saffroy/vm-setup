#!/bin/bash
set -eu

OSDISK=/scratch-nvme/vm/debian.qcow2
INSTANCE=1
SNAPSHOT=-snapshot
export TMPDIR=${TMPDIR:-/scratch-nvme/tmp/}
MEMORY=1G
BRIDGE=vmbr0

# guest devices
NETDEV=virtio-net
BLOCKDEV=virtio-blk

TOOL=$(basename $0)

usage() {
    echo "usage: $TOOL [options]"
    echo "	-d <disk image>"
    echo "	-n <instance num>"
    echo "	-w open disk image for write (default is read-only)"
    echo "	-L use non-virtio devices (legacy mode, for Windows)"
    exit 1
}

ARGS=$(getopt -o "d:n:wL" -- "$@")
[ $? = 0 ] || usage
eval set -- "$ARGS"

while : ; do
    case "$1" in
        "-d")   OSDISK="$2" ; shift 2 ;;
        "-n")   INSTANCE="$2" ; shift 2 ;;
        "-w")   SNAPSHOT="" ; shift ;;
        "-L")   NETDEV="e1000"
                BLOCKDEV="ide-hd"
                shift ;;
        "--")   shift ; break ;;
        *)      echo "$TOOL: invalid argument '$1'" ; usage ;;
    esac
done

if [ ! -f "$OSDISK" ]; then
    echo "missing disk image file: $OSDISK"
    exit 1
fi

case ${SNAPSHOT} in
    "") echo "Booting using $OSDISK in R/W mode" ;;
    *)  echo "Booting using $OSDISK in SNAPSHOT mode" ;;
esac

# good ol' user net, rather slow though
#NETOPTS="-net nic,model=e1000 -net user,hostfwd=tcp:127.0.0.1:2222-:22"
MAC=${MAC:-$(printf 'DE:AD:BE:EF:00:%02X' $INSTANCE)}
# see man tunctl for host cfg, then on guest: ifconfig eth0 192.168.0.253
# or better, use dnsmasq to provide dhcp
# NETOPTS="-netdev tap,id=net0,ifname=tap$INSTANCE,script=no,downscript=no"
# no need to provision tap interfaces with qemu bridge helper
# see https://wiki.qemu.org/Features/HelperNetworking
NETOPTS="-netdev id=net0,type=bridge,br=$BRIDGE"
NETOPTS+=" -device ${NETDEV},netdev=net0,mac=$MAC"

if false; then
    # the easy way
    DISKOPTS="-hda $OSDISK"
    DISKOPTS+=" $SNAPSHOT"
else
    # allow for more options
    if [ -z "$SNAPSHOT" ]; then
        DISKOPTS=" -blockdev node-name=disk0,driver=file,filename=$OSDISK,discard=unmap"
    else
        # create a temp qcow backed by the image
        TEMPFILE="$(mktemp -p $TMPDIR temp-vm-pid-$$.XXXXXX)"
        exec 8<$TEMPFILE  9<>$TEMPFILE
        # use cheapest compression alg.
        BACKING_FORMAT="$(qemu-img info $OSDISK |awk '/^file format:/{print $NF}')"
        qemu-img create -f qcow2 -b $(realpath $OSDISK) \
                 -F "${BACKING_FORMAT}" -o compression_type=zstd $TEMPFILE > /dev/null
        rm $TEMPFILE
        # ls -l /dev/fd/{8,9}

        # NB: we need TWO fds for a qemu fdset thingie
        # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=939413#27
        DISKOPTS=" -add-fd fd=9,set=2 -add-fd fd=8,set=2"
        DISKOPTS+=" -blockdev node-name=disk0,driver=file,filename=/dev/fdset/2,discard=unmap"
    fi
    DISKOPTS+=" -blockdev node-name=hd0,driver=qcow2,file=disk0,discard=unmap"
    DISKOPTS+=" -device ${BLOCKDEV},drive=hd0,id=ssd0"
    case "$BLOCKDEV" in
        "ide-hd")
            # mark as SSD so OS knows to issue TRIM
            DISKOPTS+=" -set device.ssd0.rotation_rate=1"
            ;;
    esac
fi

MACHINEOPTS="-enable-kvm -machine q35,accel=kvm -cpu host"
GRAPHOPTS="-vga std"
#REMOTEOPTS="-vnc none"
REMOTEOPTS=
MONITOROPTS="-monitor telnet:localhost:$((2300 + ${INSTANCE})),server,nowait"

set -x

qemu-system-x86_64 \
    -name vm${INSTANCE} -nodefaults \
    $MACHINEOPTS \
    -m $MEMORY \
    $MONITOROPTS \
    $GRAPHOPTS \
    $NETOPTS \
    $DISKOPTS \
    $REMOTEOPTS \
    "$@"
