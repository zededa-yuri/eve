#!/bin/bash

EVE="$(cd "$(dirname "$0")" && pwd)/../"
PATH="$EVE/build-tools/bin:$PATH"

process-image-template() {
    local out_templ_path="$1"
    local eve_version="$2"

    local flags
    local -a bits

    # Drop everything before the git hashcode (including the hash)
    flags="$(sed -r 's/.*[0-9a-fA-F]{8}(.*)/\1/p' <<< "${eve_version}")"
    # Drop dirty flag
    flags="$(sed -r 's/-dirty[0-9.\-]{18}//g' <<< "${flags}")"
    IFS='-' read -r -a bits <<< "${flags}"

    for bit in "${bits[@]}"; do
	echo "processing bit ${bit}"
	case "${bit}" in
	    dev)
		yq eval -i '(.services[] | select(.name == "pillar").image) |= "PILLAR_DEV_TAG"' "${out_templ_path}"
		;;
	esac
    done
}

main() {
    # local image_dir="$1"
    # local base_template="$2"
    # local out_template="$3"
    # local eve_version="$4"
    # local out_templ_path="${image_dir}/${out_template}"
    # local base_templ_path="${image_dir}/${base_template}"

    local base_templ_path="$1"
    local out_templ_path="$2"
    local eve_version="$3"

    if [ -e "${out_templ_path}".patch ]; then
	patch -p0 -o "${out_templ_path}".sed < "${out_templ_path}".patch
    else
	cp "${base_templ_path}" "${out_templ_path}".sed
    fi

    sed "s/EVE_VERSION/${eve_version}/g" < "${out_templ_path}".sed > "${out_templ_path}"

    process-image-template "${out_templ_path}" "${eve_version}"
}

main "$@"
