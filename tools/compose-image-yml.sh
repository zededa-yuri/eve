#!/bin/bash

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
}

main "$@"
