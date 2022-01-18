#!/bin/sh

do_pivot_root() {
    root_uuid="$(sed -n 's/.*root=PARTUUID=\([0-9a-fA-F-]*\).*/\1/p' < /proc/cmdline)"
    if ! root_part="$(findfs PARTUUID="${root_uuid}")"; then
	echo "Failed looking up root partition"
	return 1
    fi

    if ! IMGA=$(findfs PARTLABEL=IMGA) || ! IMGB=$(findfs PARTLABEL=IMGB); then
	echo "Failed looking up image A/B"
	return 1
    fi

    if [ "${root_part}" = "${IMGA}" ]; then
	second_part="${IMGB}"
    else
	second_part="${IMGA}"
    fi

    if ! mount "${root_part}" -t squashfs -o ro /mnt/ro-root; then
        echo "Failed mounting original root at /mnt/ro-root"
        return 1
    fi

    if ! mount -t ext4 "${second_part}" /mnt/2nd-part; then
	echo "Failed mounting 2nd-part"
	return 1
    fi

    if ! mount -t overlay -o \
          lowerdir=/mnt/ro-root,workdir=/mnt/2nd-part/root-workdir,upperdir=/mnt/2nd-part/root-upper \
          overlayfs-root /mnt/new-root; then
        echo "Failed mounting overlayfs"
        return 1
    fi

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
umount /mnt/sys
umount /mnt/proc
umount /mnt/dev
umount /mnt

exec /sbin/init
END
    )"

}

main() {
    # mount /proc
    if ! mount -t proc proc /proc; then
	echo "Failed mounting /proc"
	return 1
    fi

    # mount /proc
    if ! mount -t devtmpfs none /dev; then
	echo "Failed mounting /dev"
	return 1
    fi

    # mount /sys
    if ! mount -t sysfs none /sys; then
	echo "Failed mounting /dev"
	return 1
    fi

    # create a writable fs to then create our mountpoints
    if ! mount -t tmpfs inittemp /mnt; then
	echo "Failed mounting /mnt"
	return 1
    fi

    if ! mkdir /mnt/ro-root /mnt/2nd-part /mnt/new-root; then
	echo "Failed creating temporary mount points"
	return 1
    fi

    do_pivot_root
}

main "$@"

cat << EOF
Pivoting failed, launching shell to help investigate what went
wrong. Note that this shell is now PID 1 This allows you to call:

   /sbin/init

to continue booting EVE normally.

But keep in mind, if you exit this shell kernel will panic
EOF

exec /bin/sh
