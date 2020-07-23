#!/bin/sh
#
# Copyright (c) 2018 Zededa, Inc.
# SPDX-License-Identifier: Apache-2.0

PERSISTDIR=/var/persist
CONFIGDIR=/var/config

# The only bit of initialization we do is to point containerd to /persist
# The trick here is to only do it if /persist is available and otherwise
# allow containerd to run with /var/lib/containerd on tmpfs (to make sure
# that the system comes up somehow)
init_containerd() {
    mkdir -p "$PERSISTDIR/containerd"
    mkdir -p /var/lib
    rm -rf /var/lib/containerd
    ln -s "$PERSISTDIR/containerd" /var/lib/containerd
}

mkdir -p $PERSISTDIR
chmod 700 $PERSISTDIR
mkdir -p $CONFIGDIR
chmod 700 $CONFIGDIR

if CONFIG=$(findfs PARTLABEL=CONFIG) && [ -n "$CONFIG" ]; then
    if ! fsck.vfat -y "$CONFIG"; then
        echo "$(date -Ins -u) fsck.vfat $CONFIG failed"
    fi
    if ! mount -t vfat -o dirsync,noatime "$CONFIG" $CONFIGDIR; then
        echo "$(date -Ins -u) mount $CONFIG failed"
    fi
else
    echo "$(date -Ins -u) No separate $CONFIGDIR partition"
fi

P3_FS_TYPE="ext3"
FSCK_FAILED=0

# First lets see if we're running with the disk that hasn't been properly
# initialized. This could happen when we run in a virtualized cloud
# environment where the initial disk image gets resized to its proper
# size when EVE is started (it can also happen when you're preparing a
# live image for something like HiKey and put it dirrectly on the flash
# card bypassing using EVE's installer).
#
# The criteria we're using to determine if the disk hasn't been fully
# initialized is when it is missing both P3 (/persist) and IMGB partition
# entries. If that's the case we're willing to (potentially destructively)
# manipulate partition table. The logic here is simple: if we're missing
# both IMGB and P3 the following code is probably the *least* risky thing
# we can do.
P3=$(findfs PARTLABEL=P3)
IMGA=$(findfs PARTLABEL=IMGA)
IMGB=$(findfs PARTLABEL=IMGB)
if [ -n "$IMGA" ] && [ -z "$P3" ] && [ -z "$IMGB" ]; then
   DEV=$(echo /sys/block/*/"${IMGA#/dev/}")
   DEV="/dev/$(echo "$DEV" | cut -f4 -d/)"

   # if sgdisk complains we need to repair the GPT
   if sgdisk -v "$DEV" | grep -q 'Identified.*problems'; then
       # save a copy of the MBR + first partition entry
       # the logic here is that whatever booted us was good
       # enough to get us here, so we'd rather sgdisk disn't
       # mess up a good thing for us
       dd if="$DEV" of=/tmp/mbr.bin bs=1 count=$((446 + 16)) conv=noerror,sync,notrunc

       sgdisk -h1 -e "$DEV"

       # move 1st MBR entry to 2nd place
       dd if="$DEV" of="$DEV" bs=1 skip=446 seek=$(( 446 + 16)) count=16 conv=noerror,sync,notrunc
       # restore 1st MBR entry + first partition entry
       dd if=/tmp/mbr.bin of="$DEV" bs=1 conv=noerror,sync,notrunc
   fi

   # now that GPT itself is fixed, lets add IMGB & P3 partitions
   IMGA_ID=$(sgdisk -p "$DEV" | grep "IMGA$" | awk '{print $1;}')
   IMGB_ID=$((IMGA_ID + 1))
   P3_ID=$((IMGA_ID + 7))

   IMGA_SIZE=$(sgdisk -i "$IMGA_ID" "$DEV" | awk '/^Partition size:/ { print $3; }')
   IMGA_GUID=$(sgdisk -i "$IMGA_ID" "$DEV" | awk '/^Partition GUID code:/ { print $4; }')

   SEC_START=$(sgdisk -f "$DEV")
   SEC_END=$((SEC_START + IMGA_SIZE))

   sgdisk --new "$IMGB_ID:$SEC_START:$SEC_END" --typecode="$IMGB_ID:$IMGA_GUID" --change-name="$IMGB_ID:IMGB" "$DEV"
   sgdisk --largest-new="$P3_ID" --typecode="$P3_ID:5f24425a-2dfa-11e8-a270-7b663faccc2c" --change-name="$P3_ID:P3" "$DEV"

   # focrce kernel to re-scan partition table
   partprobe "$DEV"
   partx -a --nr "$IMGB_ID:$P3_ID" "$DEV"
fi

# We support P3 partition either formatted as ext3/4 or as part of ZFS pool
# Priorities are: ext3, ext4, zfs
if P3=$(findfs PARTLABEL=P3) && [ -n "$P3" ]; then
    P3_FS_TYPE=$(blkid "$P3"| tr ' ' '\012' | awk -F= '/^TYPE/{print $2;}' | sed 's/"//g')
    echo "$(date -Ins -u) Using $P3 (formatted with $P3_FS_TYPE), for $PERSISTDIR"

    # Loading zfs modules to see if we have any zpools attached to the system
    # We will unload them later (if they do unload it meands we didn't find zpools)
    modprobe zfs

    # XXX FIXME: the following hack MUST go away when/if we decide to officially support ZFS
    # Note that for whatever reason, it appears that blkid can only identify zfs after it has
    # been populated with some data (not just initialized). Hence this block is AFTER blkid above
    if [ "$(dd if="$P3" bs=8 count=1 2>/dev/null)" = "eve<3zfs" ]; then
        # zero out the request (regardless of whether we can convert to zfs)
        dd if=/dev/zero of="$P3" bs=8 count=1 conv=noerror,sync,notrunc
        chroot /hostfs zpool create -f -m /var/persist -o feature@encryption=enabled persist "$P3"
        # we immediately create a zfs dataset for containerd, since otherwise the init sequence will fail
        #   https://bugs.launchpad.net/ubuntu/+source/zfs-linux/+bug/1718761
        chroot /hostfs zfs create -p -o mountpoint=/var/lib/containerd/io.containerd.snapshotter.v1.zfs persist/snapshots
        P3_FS_TYPE=zfs_member
    fi

    case "$P3_FS_TYPE" in
         ext3|ext4) if ! "fsck.$P3_FS_TYPE" -y "$P3"; then
                        FSCK_FAILED=1
                    fi
                    ;;
        zfs_member) P3_FS_TYPE=zfs
                    if ! chroot /hostfs zpool import -f persist; then
                        FSCK_FAILED=1
                    fi
                    ;;
                 *) echo "P3 partition $P3 appears to have unrecognized type $P3_FS_TYPE"
                    FSCK_FAILED=1
                    ;;
    esac

    #For systems with ext3 filesystem, try not to change to ext4, since it will brick
    #the device when falling back to old images expecting P3 to be ext3. Migrate to ext4
    #when we do usb install, this way the transition is more controlled.
    #Any fsck error (ext3 or ext4), will lead to formatting P3 with ext4
    if [ $FSCK_FAILED = 1 ]; then
        echo "$(date -Ins -u) mkfs.ext4 on $P3 for $PERSISTDIR"
        #Use -F option twice, to avoid any user confirmation in mkfs
        if ! mkfs -t ext4 -v -F -F -O encrypt "$P3"; then
            echo "$(date -Ins -u) mkfs.ext4 $P3 failed"
        else
            echo "$(date -Ins -u) mkfs.ext4 $P3 successful"
            P3_FS_TYPE="ext4"
        fi
    fi

    if [ "$P3_FS_TYPE" = "ext3" ]; then
        if ! mount -t ext3 -o dirsync,noatime "$P3" $PERSISTDIR; then
            echo "$(date -Ins -u) mount $P3 failed"
        fi
    fi
    #On ext4, enable encryption support before mounting.
    if [ "$P3_FS_TYPE" = "ext4" ]; then
        tune2fs -O encrypt "$P3"
        if ! mount -t ext4 -o dirsync,noatime "$P3" $PERSISTDIR; then
            echo "$(date -Ins -u) mount $P3 failed"
        fi
    fi

    # deposit fs type into /run
    echo "$P3_FS_TYPE" > /run/eve.persist_type
    # making sure containerd uses P3 for storing its state
    init_containerd
    # this is safe, since if the mount fails the following will fail too
    # shellcheck disable=SC2046
    rmmod $(lsmod | grep zfs | awk '{print $1;}') || :
else
    echo "$(date -Ins -u) No separate $PERSISTDIR partition"
fi

UUID_SYMLINK_PATH="/dev/disk/by-uuid"
mkdir -p $UUID_SYMLINK_PATH
chmod 700 $UUID_SYMLINK_PATH
BLK_DEVICES=$(ls /sys/class/block/)
for BLK_DEVICE in $BLK_DEVICES; do
    BLK_UUID=$(blkid "/dev/$BLK_DEVICE" | sed -n 's/.*UUID=//p' | sed 's/"//g' | awk '{print $1}')
    if [ -n "${BLK_UUID}" ]; then
        ln -s "/dev/$BLK_DEVICE" "$UUID_SYMLINK_PATH/$BLK_UUID"
    fi
done

# Uncomment the following block if you want storage-init to replace
# rootfs of service containers with a copy under /persist/services/X
# each of these is considered to be a proper lowerFS
# for s in "$PERSISTDIR"/services/* ; do
#   if [ -d "$s" ]; then
#      mount --bind "$s" "/containers/services/$(basename "$s")/lower"
#   fi
# done
