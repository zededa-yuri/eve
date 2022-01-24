#!/bin/sh

get_root_part() {
    root_uuid="$(sed -n 's/.*root=PARTUUID=\([0-9a-fA-F-]*\).*/\1/p' < /proc/cmdline)"
    if ! root_part="$(findfs PARTUUID="${root_uuid}")"; then
	echo "Failed looking up root partition"
	return 1
    fi

    echo "${root_part}"
}

get_secondary_part() {
    root_part="$1"

    if ! IMGA=$(findfs PARTLABEL=IMGA) || ! IMGB=$(findfs PARTLABEL=IMGB); then
	echo "Failed looking up image A/B"
	return 1
    fi

    if [ "${root_part}" = "${IMGA}" ]; then
	second_part="${IMGB}"
    else
	second_part="${IMGA}"
    fi

    echo "${second_part}"

#    echo "root_part=${root_part} secondary_part=${second_part}"
}

prepare_secondary() {
    secondary_part="$(get_secondary_part "$(get_root_part)")"

    if ! mount -t tmpfs tmpfs /hostfs/mnt; then
	>&2 echo "Failed to create mount point"
	return 1
    fi

    second_part_mnt="/hostfs/mnt/2nd-part/"
    if ! mkdir "${second_part_mnt}"; then
	>&2 echo "Failed to create mount point ${second_part_mnt}"
	return 1
    fi

    if ! mount -t ext4 "${secondary_part}" "${second_part_mnt}"; then
	# Assuming that secondary was not used for overlay yet

	apk add e2fsprogs

	if ! mkfs.ext4 "${secondary_part}"; then
	    >&2 echo "Failed to format secondary partiton"
	    return 1
	fi

	if ! mount -t ext4 "${secondary_part}" "${second_part_mnt}"; then
	    >&2 echo "Failed to mount secondayr partition"
	    return 1
	fi

	if ! mkdir -p "${second_part_mnt}"/root-workdir || \
		! mkdir "${second_part_mnt}"/root-upper; then
	    >&2 echo "Failed creating mount points for overlayfs"
	    return 1
	fi

    fi
}


main() {
    SHORT=r,h
    LONG=reboot,help
    OPTS=$(getopt -a -n prepare-overlay --options $SHORT --longoptions $LONG -- "$@")

    eval set -- "$OPTS"

    reboot=false
    while :
    do
	case "$1" in
	    -r | --reboot )
		reboot=true
		shift 1
		;;
	    -h | --help)
		echo "This is a weather script"
		exit 2
		;;
	    --)
		shift;
		break
		;;
	    *)
		echo "Unexpected option: $1"
		;;
	esac
    done

    if ! prepare_secondary; then
	>$2 echo "failed to prepare secondary partition for dev-overlay"
	exit 1
    fi

    if [ ${reboot} = true ]; then
	kexec_sh_path=/root/kexec.sh
	if [ -e /hostfs ]; then
	    kexec_sh_path=/hostfs"${kexec_sh_path}"
	fi
	"${kexec_sh_path}" --overlay
    fi
}


main "$@"
