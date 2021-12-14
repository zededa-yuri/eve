#!/bin/sh

zfs_tuned=1

mount_path=/tmp/modules

if [ "${zfs_tuned}" = "1" ]; then
    module_path="${mount_path}"/tuned_zfs/extra
else
    module_path="${mount_path}"/standart_zfs/extra
fi

zfs_params() {
    if [ "${zfs_tuned}" = "1" ]; then
        echo "$(zfs_tuned_params)"
    else
        echo ""
    fi

}

mount_modules_override() {
    mkdir -p "${mount_path}" || return 1
    if ! mount /dev/sdc "${mount_path}"; then
	echo "Failed mounting modules overrides"
	return 1
    fi
}

zfs_dump_params() {
    params="zfs_compressed_arc_enabled \
zfs_vdev_min_auto_ashift \
zvol_request_sync \
zfs_arc_min \
zfs_arc_max \
zfs_vdev_aggregation_limit_non_rotating \
zfs_vdev_async_write_active_min_dirty_percent \
zfs_vdev_async_write_active_max_dirty_percent \
zfs_delay_min_dirty_percent \
zfs_delay_scale \
zfs_dirty_data_max \
zfs_dirty_data_sync_percent \
zfs_prefetch_disable \
zfs_vdev_sync_read_min_active \
zfs_vdev_sync_read_max_active \
zfs_vdev_sync_write_min_active \
zfs_vdev_sync_write_max_active \
zfs_vdev_async_read_min_active \
zfs_vdev_async_read_max_active \
zfs_vdev_async_write_min_active \
zfs_vdev_async_write_max_active \
"

    new_params="zfs_smoothing_scale zfs_write_smoothing"

    if [ -f /sys/module/zfs/parameters/zfs_smoothing_scale ]; then
	params="${params}" "${new_params}"
    fi

    echo "-- Module params --"
    for opt in ${params}; do
	printf "%45s: %d\n" "${opt}" "$(cat /sys/module/zfs/parameters/"${opt}")"
    done

    echo "-- Zvol params --"
    zfs get volblocksize,compression,primarycache,logbias,redundant_metadata persist/volumes/59b98be5-cca7-4a62-b36b-8ab35b69b1a9.0
}

zfs_insmod() {
    dependencies="spl/spl.ko nvpair/znvpair.ko zcommon/zcommon.ko \
                    icp/icp.ko avl/zavl.ko lua/zlua.ko \
                    unicode/zunicode.ko zstd/zzstd.ko"

    for dep in ${dependencies}; do
	if ! insmod "${module_path}/${dep}"; then
	    echo "failed to load ${dep}"
	    return 1
	fi
    done

    if ! insmod "${module_path}/zfs/zfs.ko" "$(zfs_params)"; then
	echo "failed to load zfs module"
	return 1
    fi
}

zfs_tuned_params() {
    # Constants
    set -e
    target_drive=sdb
    zfs_arc_min="$(echo "256*1024*1024" | bc)"

    # can't go lowere then 384 MiB
    zfs_arc_max_minimum="$(echo "384*1024*1024" | bc)"

    # Formulas
    target_size="$(cat /sys/class/block/"${target_drive}"/size)"
    target_size="$(echo "${target_size} * 512" | bc)"

    bc_script="
    metadata_estimate=(${target_size}*0.3/100);
    arc_max=(${zfs_arc_min} + metadata_estimate);
    if (arc_max < ${zfs_arc_max_minimum})
       arc_max = ${zfs_arc_max_minimum}
    ;
    arc_max
    "

    zfs_arc_max="$(echo "${bc_script}" | bc)"
    zfs_dirty_data_max="$(echo "${zfs_arc_max}"/2 | bc)"

    zfs_options="zfs_compressed_arc_enabled=0 \
zfs_vdev_min_auto_ashift=12 \
zvol_request_sync=0 \
zfs_arc_min=${zfs_arc_min} \
zfs_arc_max=${zfs_arc_max} \
zfs_vdev_aggregation_limit_non_rotating=$(echo "1024*1024" | bc) \
zfs_vdev_async_write_active_min_dirty_percent=10 \
zfs_vdev_async_write_active_max_dirty_percent=30 \
zfs_delay_min_dirty_percent=40 \
zfs_delay_scale=800000 \
zfs_dirty_data_max=${zfs_dirty_data_max} \
zfs_dirty_data_sync_percent=15 \
zfs_prefetch_disable=1 \
\
zfs_vdev_sync_read_min_active=35 \
zfs_vdev_sync_read_max_active=35 \
zfs_vdev_sync_write_min_active=35 \
zfs_vdev_sync_write_max_active=35 \
zfs_vdev_async_read_min_active=1 \
zfs_vdev_async_read_max_active=10 \
zfs_vdev_async_write_min_active=1 \
zfs_vdev_async_write_max_active=10 \
zfs_smoothing_scale=50000 \
zfs_write_smoothing=5 \
"

    echo "${zfs_options}"
#    zfs_dump_params

}

zfs_module_load_override() {
    echo "------ Executing zfs module overrides ------"
    mount_modules_override || return 1
    sleep 3
    zfs_insmod || return 1

    lsmod | grep zfs
    echo "------ Overrides executed successfuly ------"
}


zfs_free_vhost() {
    wwpn="$(grep -A 4 vhost-disk1 /run/domainmgr/xen/xen1.cfg)" || exit 1
    wwpn="$(echo "${wwpn}" | grep wwpn)" || exit 1
    wwpn="$(echo "${wwpn}" | awk -F "=" '{/wwpn/; gsub(/"/, "", $2); gsub(" ", "" ,$2); print $2}')" || exit 1

    echo "${wwpn}"

    rm /sys/kernel/config/target/vhost/"${wwpn}"/tpgt_1/lun/lun_0/iblock || exit 1
    rmdir /sys/kernel/config/target/vhost/"${wwpn}"/tpgt_1/lun/lun_0 || exit 1
    rmdir /sys/kernel/config/target/core/iblock_0/59b98be5-cca7-4a62-b36b-8ab35b69b1a9#0 || exit 1
    zfs destroy persist/volumes/59b98be5-cca7-4a62-b36b-8ab35b69b1a9.0 || exit 1
}

zfs_create_zvol_tuned() {
    zfs create -p -V 200G \
	-o volmode=dev \
	-o compression=zstd \
	-o volblocksize=16k \
	-o primarycache=metadata \
	-o logbias=throughput \
	-o redundant_metadata=most \
	persist/volumes/59b98be5-cca7-4a62-b36b-8ab35b69b1a9.0
}
