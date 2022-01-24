#!/bin/sh

do_kexec() {
    kernel="$1"
    init="$2"
    cmdline="$(cat /proc/cmdline) init="

    cmdline="$(cat /proc/cmdline)"
    if [ -n "${init}" ]; then
	cmdline="${cmdline} init=${init}"
    fi

    kexec -l -s "${kernel}" --append "${cmdline}"
    kexec -e -s "${kernel}"
}

main() {
    SHORT=k:,i:,o,h
    LONG=kernel:,init:,overlay,help
    OPTS=$(getopt -a -n kexec --options $SHORT --longoptions $LONG -- "$@")

    eval set -- "$OPTS"

    overlay=false
    kernel=/hostfs/boot/kernel
    init=""
    while :
    do
	case "$1" in
	    -k | --kernel )
		kernel="$2"
		shift 2
		;;
	    -i | --init )
		init="$2"
		shift 2
		;;
	    -o | --overlay )
		overlay=true
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

    if [ "${overlay}" = true ]; then
	init="/root/dev-overlay.sh"
    fi

    do_kexec "${kernel}" "${init}"
}

main "$@"
