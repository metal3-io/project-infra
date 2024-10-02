#!/bin/bash

# This script is intended to be used in a initrd/initramfs built by
# dracut. The purpose of the script is to unlock and mount the root partition
# and unlock the cloud-init config drive.
#
# The script works also without encryption but it doesn't support the
# scenario when only the config drive is encrypted.
#
# The script has 1 mandatory and 3 optional positional arguments
# Such as:
# - path to the device file of the root partition (mandatory)
# - path to the script that provides the encryption key in plain text format
# - the partition number of the config-drive
# - flag to run in dry run mode (nothig will get created/unlocked/mounted

set -eu

_is_luks() {
    # check blkid record of a device and determine if it is luks encrypted
    # arguments - any path to device file e.g. /dev/sd*,
    # /dev/disk/by-label/<your_label>,by-uuid/<your_id> etc..
    local _record _half_type _full_type _device_path
    _device_path="$1"
    _record="$(blkid "${_device_path}")"
    _half_type="${_record##*TYPE=\"}"
    _full_type="${_half_type%%\"*}"
    if [[ "crypto_LUKS" == "${_full_type}" ]]; then
        return 0
    fi
    return 1
}

_get_partition_from_blkid() {
    # remove all but the device name of the blkid record
    # arguments - any path to deevice file e.g. /dev/sd*,
    # /dev/disk/by-label/<yourlabel>,by-uuid/<your_id> etc..
    local _record _partition_device_path _partition _uuid _blkid
    _partition_device_path="$1"
    _record="$(blkid "${_partition_device_path}")"
    # take the UUID then, run regular blkid w/o arguments and match the UUID
    #_record="${_record##*PARTUUID=}"
    #_uuid="${_record%% *}"
    _uuid="${_record##*PARTUUID=}"

    blkid | while read -r _pname _ _ _iter_uuid; do
       if [[ "${_uuid}" == "${_iter_uuid##*PARTUUID=}" ]]; then
            _partition="${_pname%%\:*}"
            printf "%s" "${_partition##*/}"
            break
       fi
    done
}

_get_part_prefix_for_device() {
    # some block device type will have "p" or "part" partition number
    # prefix associated with it, this function return's the partition prefix
    # arguments - name of a partition that can be found in /proc/partitions
    #             and belongs to the device/disk under analysis
    local _partition
    _partition="$1"
    if [[ "${_partition}" =~ nvme|loop|mmcblk ]]; then
        if [[ "${_partition}" =~ .*part.* ]]; then
            printf "part"
        else
            printf "p"
        fi
    fi
}

_count_parts_for_disk() {
    # Match how many partitions belong to a given disk based on
    # data available in /proc/partitions
    # arguments - name of the disk under /dev (not path just name)
    local _count _disk
    _disk="$1"
    # both the disk and the partitions are listed in the /proc/partitions so
    # there will be an extra record that has to be accounted for
    _count=-1
    # read command will also cut up the columns
    while read -r _ _ _ _part; do
        # if the major device number matches then we have match
        if [[ "${_part}" =~ ${_disk} ]]; then
            _count=$((_count + 1))
        fi
    done < "/proc/partitions"
    printf "%s" "${_count}"
}

_dry_run() {
    # if dry_run mode is enabled commands are just printed not executed
    # arguments - anything
    if [[ "${dry_run}" == "false" ]]; then
        "$@"
    else
        printf "DRY_RUN: "
        printf "%s " "${@}"
        printf "\n"
    fi
}

# Start of the execution

root_device_path="${1:?}"
key_script="${2:-/etc/tpm2-unseal-key.sh}"
config_drive_part_num="${3:-}"
dry_run="${4:-false}"
key="${key_script}"

printf "INFO: unlock script has been started with the following arguments:\n"
printf "Root device:%s, key script:%s, config-drive partition number:%s, " \
    "${root_device_path}" "${key_script}" "${config_drive_part_num}"
printf "dry run:%s\n" "${dry_run}"

# create the mount point for the root file system and evaluate the
# key script
if [[ "${dry_run}" == "false" ]]; then
    key=<("${key_script}")
    mkdir "/realroot"
fi

# different workflows depending on the presence of encryption
# --------------------------------------------------------------------
# nvme, mmc/sd card and loop devices have a partition number prefix
# e.g./dev/nvme0n1 <--> /dev/nvme0n1p1
# --------------------------------------------------------------------
# It is expected that the last partition on the root device is the
# config drive partition thus that is the default logic. In case the user
# specified a value for `config_drive_part_num` the partition count will
# be discarded and the value of `config_drive_part_num` will be used instead.
if _is_luks "${root_device_path}"; then
    printf "Mounting encrypted %s\n" "${root_device_path}"
    _dry_run "/usr/lib/systemd/systemd-cryptsetup" "attach" "realroot" \
            "${root_device_path}" "${key}" "luks"
    _dry_run "mount" "/dev/mapper/realroot" "/realroot"
    root_partition="$(_get_partition_from_blkid "${root_device_path}")"
    part_prefix="$(_get_part_prefix_for_device "${root_partition}")"
    root_device="${root_partition%"${part_prefix}"*}"
    part_count="$(_count_parts_for_disk "${root_device}")"
    config_drive_common="/dev/${root_device}${part_prefix}"
    if [[ -z "${config_drive_part_num}" ]]; then
        config_drive_path="${config_drive_common}${part_count}"
    else
        config_drive_path="${config_drive_common}${config_drive_part_num}"
    fi
    if _is_luks "${config_drive_path}"; then
        printf "Unlocking config drive %s\n" "${config_drive_path}"
        printf "INFO: config-drive:%s disk:%s part_count:%s " \
            "${config_drive_path}" "${root_device}" "${part_count}"
        printf "root_partition:%s prefix:%s\n" "${root_partition}" \
            "${part_prefix}"
        _dry_run "/usr/lib/systemd/systemd-cryptsetup" "attach" "config-2" \
                "${config_drive_path}" "${key}" "luks"
        # At this stage the config drive does not need to be mounted, after
        # it is unlocked cloud-init can identify and mount the config drive
        # on its own
    fi

else
    printf "Mounting NON encrypted volume!!!\n"
    _dry_run "mount" "${root_device_path}"  "/realroot"
fi
