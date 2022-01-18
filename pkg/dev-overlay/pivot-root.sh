#!/bin/sh


do_pivot_root() {
    echo "Mounting original root to /mnt/ro-root"
    if ! mount /dev/sda2 -t squashfs -o ro /mnt/ro-root; then
        echo "Failed mounting original root at /mnt/ro-root"
        return 1
    fi

    echo "Mounting overlayfs"
    if ! mount -t overlay -o \
          lowerdir=/mnt/ro-root,workdir=/mnt/2nd-part/root-workdir,upperdir=/mnt/2nd-part/root-upper \
          overlayfs-root /mnt/new-root; then
        echo "Failed mounting overlayfs"
        return 1
    fi

    echo "Pivoting rootfs"
    cd /mnt/new-root/ || return 1
    pivot_root . mnt

    if ! mkdir -p /ro-root /2nd-part; then
        echo "Failed creating new mount points"
    fi

    echo "Launching init in new root"
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
