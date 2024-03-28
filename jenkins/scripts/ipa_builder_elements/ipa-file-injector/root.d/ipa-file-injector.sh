#!/bin/bash
set -eu

# Behaviour of the scritp is the following:
# Try and mount the config-drive; if it exists, then copy files
# to locations as specified in the file_injection.manifest of the
# config-drive.

copy_files_from_drive() {
    local mount_point="$1"
    local manifest="$2"
    if ! [[ -f "${manifest}" ]]; then
        echo "ERROR: The config-drive's file injection manifest is not present here: ${manifest}"
        exit 1
    fi
    while IFS=":" read -r src dst perm; do
        # Copy file based on manifest definition.
        if ! cp -r "${mount_point}/${src}" "${dst}"; then
           echo "ERROR: command 'cp -r ${mount_point}/${src} ${dst}' has failed!"
           exit 1
        fi
        # Set permissions for newly copied file.
        if ! chmod "${perm:-644}" "${dst}"; then
           echo "ERROR: command 'chmod ${perm:-644} ${dst}' has failed!"
           exit 1
        fi
    done < "${manifest}"
}

configure_services() {
    local mount_point="$1"
    local manifest="$2"
    if ! [[ -f "${manifest}" ]]; then
        echo "INFO: The config-drive's service configuration manifest is not present here: ${manifest}"
        echo "INFO: skipping systemd service configuration step."
        return 0
    fi
    # Refresh the list of available unit files.
    systemctl daemon-reload
    while IFS=":" read -r service action; do
        # Execute state transition on service.
        if ! systemctl "${action}" "${service}"; then
           echo "ERROR: command 'systemctl ${action} ${service}' has failed!"
           exit 1
        fi
    done < "${manifest}"
}

# In case tehre is no config-drive label specifed, the script will
# use the default config-2 label.
# Depending on the cloud, it may have `vfat` config drive which
# comes with a capitalized label rather than all lowercase.

CONFIG_DRIVE_LABEL="${FILE_INJECTOR_CONFIG_DRIVE_LABEL:-}"
MOUNT_POINT="/mnt/config"

if [[ -z "${CONFIG_DRIVE_LABEL}" ]]; then
    if blkid -t LABEL="config-2" ; then
        CONFIG_DRIVE_LABEL="config-2"
    elif blkid -t LABEL="CONFIG-2" ; then
        CONFIG_DRIVE_LABEL="CONFIG-2"
    else
        echo "ERROR: There is no config-drive label specified and the default label is not present!"
        exit 1
    fi
fi

# Mount the config-drive
# Some failures such of blkid our mount are ignored:
# Mount failure is ignored as it could happen that the mounts already exist and that is fine.
# blkid failures are ignored as they are handled explicitly later to help with debugging.
mkdir -p "${MOUNT_POINT}"
BLOCKDEV=$(blkid -L "${CONFIG_DRIVE_LABEL}") || true
if [[ -z "${BLOCKDEV}" ]]; then
    echo "ERROR: The block device with the ${CONFIG_DRIVE_LABEL} label can't be found!"
    exit 1
fi
TYPE=$(blkid -t LABEL="${CONFIG_DRIVE_LABEL}" -s TYPE -o value || true )

# Mounting won't fail if the mount already exists
# If the mount didn't exists at all it is expected to fail in the copy_files_from_drive function
if [[ "${TYPE}" == 'vfat' ]]; then
    mount -t vfat -o umask=0077 "${BLOCKDEV}" "${MOUNT_POINT}" || true
elif [[ "${TYPE}" == 'iso9660' ]]; then
    mount -t iso9660 -o ro,mode=0700 "${BLOCKDEV}" "${MOUNT_POINT}" || true
else
    mount -o mode=0700 "${BLOCKDEV}" "${MOUNT_POINT}" || true
fi

# Execute the copying process
copy_files_from_drive "${MOUNT_POINT}" "${MOUNT_POINT}/file_injection.manifest"
configure_services "${MOUNT_POINT}" "${MOUNT_POINT}/service_config.manifest"
