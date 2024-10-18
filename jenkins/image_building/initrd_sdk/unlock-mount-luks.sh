#!/bin/bash

# This script is intended to be used in a initrd/initramfs built by
# dracut. The purpose of the script is to unlock and mount the root partition
# and unlock the cloud-init config drive.
#
# The script has 1 optional positional argument and 8 configuration options
# set via a configuration file
# Positional argument:
# - FS path of the configuration file
# Config file parameters:
# - key_script: path to the script that provides the encryption key in plain
#   text format
# - auth: key to open the key storage
# - secret_address: address/name/id of the key in the key storage
# - root_dev_part_path: the root device partition device file path
# - config_drive_dev_path: path to the device file of the root partition
# - config_drive_part_num: the partition number of the config-drive
# - dry_run: to run in dry run mode (nothing gets created/unlocked/mounted)
# - no_preparation: skips the execution of the preparation function
#   LUKS and TPM2.0 tool chains won't be tested
#
# External tools required by this script:
# - tpm2-tools
# - systemd-cryptsetup and related dm_crypt kernel module and libarary
# - mkdir
# - modprobe
# - lsmod
# - blkid
# During build, the dracut modules crypt, dm and tpm2-tss modules supposed to
# provide all the dependencies but it is recommended to check that
# all the libraries and kernel modules are present.
#
# Precedence of the partition detection process, the higher in the list
# the higher in precedence:
# Root partition:
# - /dev device path relative to the initrd root fs
# - auto detection based on custom partition label specified via kernel args
# - auto detection based on default partition label
# Config drive partition:
# - /dev device path relative to the initrd root fs
# - auto detection based on custom partition label specified via kernel args
# - auto detection based on default partition label
# - auto detection based on root device and partition index number
# - auto detection by selecting the last partition on the root device
#
# The script evaluates the root partition and the config drive separately
# thus scenarios where all, one or none of these partitions are encrypted are
# all supported.
#
# If root partition is not specified and can't be auto detected the script
# will exit with error code 1.

set -eu

_is_luks() {
    # Check blkid record of a device and determine if it is luks encrypted.
    # arguments - any path to device file e.g. /dev/sd*,
    # /dev/disk/by-label/<your_label>,by-uuid/<your_id> etc..
    local _record _half_type _full_type _device_path
    _device_path="${1:-}"
    if [[ -z "${_device_path}" ]]; then
        printf "false"
        return 1
    fi
    _record="$(blkid "${_device_path}")"
    _half_type="${_record##*TYPE=\"}"
    _full_type="${_half_type%%\"*}"
    if [[ "crypto_LUKS" == "${_full_type}" ]]; then
        printf "true"
        return 0
    fi
    printf "false"
    return 1
}

_get_partition_from_blkid() {
    # Remove all but the device name of the blkid record.
    # arguments - any path to device file e.g. /dev/sd*,
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
    # Some block device type will have "p" or "part" partition number
    # prefix associated with it, this function returns the partition prefix.
    # nvme, mmc/sd card and loop devices have a partition number prefix
    # e.g./dev/nvme0n1 <--> /dev/nvme0n1p1
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
    # Count how many partitions belong to a given disk based on
    # data available in /proc/partitions.
    # arguments - name of the disk under /dev (not path just name)
    local _count _disk
    _disk="$1"
    # both the disk and the partitions are listed in the /proc/partitions so
    # there will be an extra record that has to be accounted for
    _count=-1
    while read -r _ _ _ _part; do
        if [[ "${_part}" =~ ${_disk} ]]; then
            _count=$((_count + 1))
        fi
    done < "/proc/partitions"
    printf "%s" "${_count}"
}

_find_disk_for_partition() {
    # Finds what disk is related to the given partition based on
    # data available in /proc/partitions.
    # arguments - name of the disk under /dev (not path just name)
    local _partition
    _partition="$1"
    while read -r _ _ _ _candidate; do
        # the first record that could match the partition name is the
        # device name as /proc/partitions is an ordered list
        if [[ -z "${_candidate}" ]]; then
            continue
        fi
        if [[ "${_partition}" =~ ^${_candidate}[a-z0-9]*$ ]]; then
            printf "%s" "${_candidate}"
            break
        fi
    done < "/proc/partitions"
}

_dry_run() {
    # When dry_run mode is enabled commands are just printed not executed.
    # Arguments:
    # - anything
    if [[ "${dry_run}" == "false" ]]; then
        "$@"
    else
        printf "DRY_RUN: "
        printf "%s " "${@}"
        printf "\n"
    fi
}

_wait_sec() {
    # Introduce a 1 second delay using the read command
    # sleep might not be available but this way the script stresses.
    # the CPU less
    # Arguments:
    # - number of seconds to wait
    read -r -t "$1" < /dev/zero || true
}

_is_module_builtin() {
    # Check if a kernel module is "built-in" or modular.
    # Arguments:
    # - the name of the module to be tested
    local _module
    _module="$1"
    while read -r _attribute _value; do
        if [[ "${_attribute}" == "filename:" ]]; then
            if [[ "${_value}" == "(builtin)" ]]; then
                return 0
            fi
            return 1
        fi
    done < <(modinfo "${_module}")
    return 1
}

_preparation() {
    # Checks if the TPM2.0 and LUKS related tooling and drivers are available.
    # Exit with fault code 1 if the checks fail or the timeout is reached.
    # Arguments
    # - maximum number of retries
    local _cnt _limit _ready _exp_num_checks
    # all of the above listed vars are used as numeric values
    declare -i _cnt _limit _ready
    _retry_limit="${1:?}"
    _cnt=0
    _ready=0
    _exp_num_checks=3
    while [[ "${_cnt}" -lt "${_retry_limit}" ]]; do
        local _luks_probe _result _tpm_result _crypt_lsmod _dm_lsmod _ready
        # luks_probe, _result are numeric values not boolean
        # _crypt_lsmod, _dm_lsmod are used as booleans
        declare -i _luks_probe _result
        set +e
        # read the persistent "handles" list from the TPM to verify
        # that the tpm2 tool chain is in place and working
        tpm2 getcap handles-persistent
        _tpm_result="$?"
        # Verify that the modules are present and can be loaded
        _luks_probe=0
        modprobe dm_mod
        _result="$?"
        _luks_probe=$((_luks_probe + _result))
        modprobe dm_crypt
        _result="$?"
        _luks_probe=$((_luks_probe + _result))
        set -e
        if [[ "${_luks_probe}" -gt 0 ]]; then
            # No reason to recheck if the modules can't be loaded they
            # are most likely missing or incompatible
            printf "INFO: dm_mod or dm_crypt modules can't be loaded!\n"
            exit 1
        fi
        # Verify that the modules are loaded successfully
        _crypt_lsmod=1
        _dm_lsmod=1
        while read -r _mod_name _ _ _; do
            if [[ "${_mod_name}" == "dm_crypt" ]]; then
                _crypt_lsmod=0
            elif [[ "${_mod_name}" == "dm_mod" ]]; then
                _dm_lsmod=0
            fi
        done < <(lsmod)
        # If any of the models are seemingly not loaded that might be
        # because lsmod is not displaying builtin modules so it has to
        # be checked if a module is not loaded because it is builtin or
        # because it can't load properly
        if [[ "${_dm_lsmod}" -eq 1 ]]; then
            _dm_lsmod=$(_is_module_builtin "dm_mod")
        fi
        if [[ "${_crypt_lsmod}" -eq 1 ]]; then
            _crypt_lsmod=$(_is_module_builtin "dm_crypt")
        fi
        # Final checks
        _ready=0
        if [[ "${_crypt_lsmod}" -eq 0 ]]; then
            printf "INFO: dm_crypt check for LUKS: SUCCESS!\n"
            _ready=$((++_ready))
        else
            printf "WARNING: dm_crypt check for LUKS: FAIL!\n"
        fi
        if [[ "${_dm_lsmod}" -eq 0 ]]; then
            printf "INFO: dm_mod for LUKS: SUCCESS!\n"
            _ready=$((++_ready))
        else
            printf "WARNING: dm_mod check for LUKS: FAIL!\n"
        fi
        if [[ "${_tpm_result}" -eq 0 ]]; then
            printf "INFO: tpm2 persistent access to handles: SUCCESS!\n"
            _ready=$((++_ready))
        else
            printf "WARNING: tpm2 persistent access to handles: FAIL!\n"
        fi
        if [[ "${_ready}" -eq "${_exp_num_checks}" ]]; then
            printf "INFO: All checks are OK, proceeding with decryption!\n"
            break
        else
            printf "WARNING: Some checks have FAILED, waiting 1s then retry!\n"
        fi
        _cnt=$((++_cnt))
        _wait_sec 1
    done
    if [[ "${_ready}" -ne "${_exp_num_checks}" ]]; then
        printf "ERROR: Some checks have FAILED, TIMEOUT has been reached!\n"
        exit 1
    fi
}

_get_kernel_param_value() {
    # This function returns the value of a kernel command line parameter if
    # the parameter exists and has separate value field.
    # Arguments:
    # - The "key/name" of the parameter that the function should be looking for
    local _target_param _params
    _target_param="${1:?}"

    if [[ ! -r "/proc/cmdline" ]]; then
        printf "ERROR: /proc/cmdline is not available something is wrong!\n"
        exit 1
    fi
    IFS=" " read -r -a _params < "/proc/cmdline"

    for _param in "${_params[@]}"; do
        _key="${_param%=*}"
        _value="${_param#*=}"
        if [[ "${_target_param}" == "${_key}" ]] &&
           [[ "${_key}" != "${_value}" ]];
        then
            printf "%s" "${_value}"
            break
        fi
    done
}

_detect_part_label_kernel_param() {
    # Detects GPT partitions based on the presence of kernel cmdline
    # parameter defined in the key=value format where the value is the
    # GPT partition label.
    # Arguments:
    # - the "key" part of the kernel command line argument
    # - optional default partition label to look for
    local _param _label _default_label _dev_path
    _param=${1:?}
    _default_label=${2:-}
    _label="$(_get_kernel_param_value "${_param}")"
    if [[ -z "${_label}" ]]; then
        _label="${_default_label}"
    fi
    _dev_path="/dev/disk/by-partlabel/${_label}"
    if [[ ! -r "${_dev_path}" ]]; then
        return
    fi
    printf "%s" "${_dev_path}"
}

_detect_root() {
    # This function checks the kernel command line variables and checks if the
    # variable p.root_label is present, if present with a non empty value
    # then the value will be return otherwise nothing will be returned.
    # In case the label can't be found the function will default to looking
    # for the p.lxroot label.
    local _root_dev
    _root_dev="$(_detect_part_label_kernel_param p.root_label p.lxroot)"
    printf "%s" "${_root_dev}"
}

_detect_config() {
    # This function checks the kernel command line variables and checks if the
    # variable p.config_label is present, if present with a non empty
    # value then the value will be return otherwise nothing will be returned.
    # In case the label can't be found the function will default to looking
    # for the p.config-2 label.
    local _cfg_dev
    _cfg_dev="$(_detect_part_label_kernel_param p.config_label p.config-2)"
    printf "%s" "${_cfg_dev}"
}

# Start of the execution

config="${1:-/etc/unlock_conf}"

if [[ -r "${config}" ]]; then
    printf "INFO: Executing script with configuration from:%s!\n" "${config}"
    # shellcheck disable=SC1090
    . "${config}"
else
    printf "WARNING: Executing script with default configuration!\n"
fi

# Config variables, only configurable via the config file:
# key management config
key_script="${key_script:-/etc/tpm2-unseal-key.sh}"
auth="${auth:-secret}"
secret_address="${secret_address:-0x81010002}"
# root partition config
root_dev_part_path="${root_dev_part_path:-$(_detect_root)}"
# config drive partition config
config_drive_dev_path="${config_drive_dev_path:-$(_detect_config)}"
config_drive_part_num="${config_drive_part_num:-}"
# dependency checks confg
preparation_timeout="${preparation_timeout:-5}"
# test config
dry_run="${dry_run:-false}"
no_preparation="${no_preparation:-false}"
# Place the keyfile in a tmpfs backed up by system memory
key="/dev/shm/key_file"

printf "INFO: unlock script has been started with the following arguments:\n"
printf "root partition dev path:%s\nconfig-drive partition number:%s\n" \
    "${root_dev_part_path:-auto}" "${config_drive_part_num:-auto}"
printf "config-drive partition dev path:%s\nkey script:%s\n" \
    "${config_drive_dev_path:-auto}" "${key_script}"
printf "DRY RUN MODE:%s\n" "${dry_run}"

# If there is not root partition target there is no reason to continue
if [[ -z "${root_dev_part_path}" ]]; then
    printf "ERROR: no root partition was specified, auto detection failed!\n"
    exit 1
fi

# Checking need for decryption and generating config drive metadata
root_partition="$(_get_partition_from_blkid "${root_dev_part_path}")"
part_prefix="$(_get_part_prefix_for_device "${root_partition}")"
root_device="$(_find_disk_for_partition "${root_partition}")"
part_count="$(_count_parts_for_disk "${root_device}")"
config_drive_common="/dev/${root_device}${part_prefix}"
if [[ -z "${config_drive_part_num}" ]] && [[ -z "${config_drive_dev_path}" ]];
then
    config_drive_dev_path="${config_drive_common}${part_count}"
elif [[ -n "${config_drive_part_num}" ]] &&
     [[ -z "${config_drive_dev_path}" ]];
then
    config_drive_dev_path="${config_drive_common}${config_drive_part_num}"
fi
printf "INFO: preview of generated configuration drive metadata:\n"
printf "config-drive:%s\ndisk:%s\npart_count:%s\n" \
    "${config_drive_dev_path}" "${root_device}" "${part_count}"
printf "root_partition:%s\nprefix:%s\n" "${root_partition}" \
    "${part_prefix}"
if [[ "/dev/${root_partition}" == "${config_drive_dev_path}" ]]; then
    printf "WARNING: Config drive candidate matches the root partition!\n"
    printf "WARNING: Real config drive was not detected!\n"
    config_drive_dev_path=""
fi
set +e
is_root_crypt=$(_is_luks "${root_dev_part_path}")
printf "INFO: root encrypted: %s\n" "${is_root_crypt}"
is_config_crypt=$(_is_luks "${config_drive_dev_path}")
printf "INFO: config encrypted: %s\n" "${is_config_crypt}"
set -e

# If decryption is required for at least one partition then check the tool
# chain integrity
if [[ "${is_root_crypt}" == "true" ]] || [[ "${is_config_crypt}" == "true" ]];
then
    if [[ "${no_preparation}" != "true" ]]; then
        _preparation "${preparation_timeout}"
    fi
    # No _dry_run function needed, the key script has its own dry run mode
    "${key_script}" "${secret_address}" "${auth}" "${dry_run}" > "${key}"
    chmod 640 "${key}"
fi

# Create the mount point for the root file system.
if [[ "${dry_run}" == "false" ]]; then
    mkdir "/realroot"
fi

# Different workflows depending on the presence of encryption!
# Root partition
if [[ "${is_root_crypt}" == "true" ]]; then
    printf "Mounting encrypted %s\n" "${root_dev_part_path}"
    _dry_run "/usr/lib/systemd/systemd-cryptsetup" "attach" "realroot" \
            "${root_dev_part_path}" "${key}" "luks,timeout=60,headless=true"
    _dry_run "mount" "/dev/mapper/realroot" "/realroot"
else
    printf "Mounting NON encrypted volume!!!\n"
    _dry_run "mount" "${root_dev_part_path}"  "/realroot"
fi
# Config drive partition
if [[ "${is_config_crypt}" == "true" ]]; then
    # Create an empty file to signal to other services that the config
    # drive was also encrypted, other services might want to know
    # if they need to keep an eye out for the config drive
    true > "/tmp/crypt_config"
    printf "Unlocking config drive %s\n" "${config_drive_dev_path}"
    _dry_run "/usr/lib/systemd/systemd-cryptsetup" "attach" "config-2" \
            "${config_drive_dev_path}" "${key}" "luks,timeout=60,headless=true"
    # At this stage the config drive doesn't need to be mounted, after the
    # partition is unlocked cloud-init can identify and mount the config drive.
fi
