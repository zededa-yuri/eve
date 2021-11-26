#!/bin/sh

module_path=/tmp/modules/zfs-test/extra

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

    for opt in ${params}; do
	printf "%45s: %d\n" "${opt}" "$(cat /sys/module/zfs/parameters/"${opt}")"
    done
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

    if ! insmod "${module_path}/zfs/zfs.ko" "$(zfs_tuned_params)"; then
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
\
"
# zfs_smoothing_scale=50000 \
# zfs_write_smoothing=5 \
# "

    echo "${zfs_options}"
#    zfs_dump_params

}
