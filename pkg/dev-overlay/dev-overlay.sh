#!/bin/sh


echo "----- overlay init script ----"

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

    # create a writable fs to then create our mountpoints
    if ! mount -t tmpfs inittemp /mnt; then
	echo "Failed mounting /mnt"
	return 1
    fi

    if ! mkdir /mnt/ro-root /mnt/2nd-part /mnt/new-root; then
	echo "Failed creating temporary mount points"
	return 1
    fi

    if ! mount -t ext4 /dev/sda3 /mnt/2nd-part; then
	echo "Failed mounting 2nd-part"
	return 1
    fi

    source /mnt/2nd-part/tools/pivot-root.sh
    pivot_root
}

main "$@"

cat << EOF
Pivoting failed, launching shell. Note that this shell is now PID 1
This allows you to call:

   /sbin/init

to continue booting EVE normally.

But keep in mind, if you exit this shell kernel will panic
EOF

exec /bin/sh
