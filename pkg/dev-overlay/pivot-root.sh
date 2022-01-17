#!/bin/sh


pivot_root() {
    if ! mount /dev/sda2 -t squashfs -o ro /mnt/ro-root; then
        echo "Failed mounting original root at /mnt/ro-root"
        /bin/sh
        return 1
    fi

    if ! mount -t overlay -o \
          lowerdir=/mnt/ro-root,workdir=/mnt/2nd-part/root-workdir,upperdir=/mnt/2nd-part/root-upper \
          overlayfs-root /mnt/new-root; then
        echo "Failed mounting overlayfs"
        /bin/sh
        return 1
    fi

    cd /mnt/new-root/ || return 1
    pivot_root . mnt

    if ! mkdir -p /ro-root /2nd-part; then
        echo "Failed creating new mount points"
        /bin/sh
    fi

    exec chroot . sh -c "$(cat <<END
if ! mount --move /mnt/mnt/ro-root/ /ro-root; then
   echo "Failed to move original root mountpoint (aka lower)"
   /bin/sh
fi

if ! mount --move /mnt/mnt/2nd-part/ /2nd-part; then
   echo "Failed to move 2nd partition mount point (contains upper)"
   /bin/sh
fi

umount /mnt/mnt
umount /mnt/proc
umount /mnt/dev/

exec /sbin/init
END
    )"

}
