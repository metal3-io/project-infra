#!/usr/bin/env bash

set -eu

# Description:
# Runs in main integration cleanup job defined in jjb.
# Consumed by clean_resources.pipeline and cleans any leftover metal3ci vms
# every 6 hours.
#   Requires:
#     - source openstack.rc file
# Usage:
#  clean_resources.sh
#
CLIENT_VERSION="7.0.0"

cleanup() {
    # Get the current date and time in seconds since the epoch
    current_time=$(date +%s)

    # Define the age threshold (6 hours in seconds)
    age_threshold=$((6 * 60 * 60))

    # List all servers and loop over their IDs and Names
    openstack server list -f value -c ID -c Name | while read -r server_id server_name; do
        # Check if the server name starts with "metal3ci-"
        if [[ "${server_name}" == metal3ci-* ]]; then
            # Get the creation date of the server
            created_at=$(openstack server show "${server_id}" -f value -c created)

            # Convert server creation date to seconds since the epoch
            server_time=$(date --date="${created_at}" +%s)

            # Calculate the age of the server
            server_age=$((current_time - server_time))

            # Check if the server is older than 6 hours
            if [[ "${server_age}" -gt "${age_threshold}" ]]; then
                echo "Deleting server: ${server_id} (Name: ${server_name}, Created at: ${created_at})"
                # Delete the server
                openstack server delete "${server_id}"
            fi
        fi
    done
}

sudo apt install -y python3.12-venv

rm -rf venv
python3 -m venv venv

# shellcheck source=/dev/null
. venv/bin/activate
# Install openstack client
pip install python-openstackclient=="${CLIENT_VERSION}"
# export openstackclient path
export PATH="${PATH}:${HOME}/.local/bin"

#unset openstack variables
unset "${!OS_@}"

# Cleaning up Private cloud resources
export OS_USERNAME="${OPENSTACK_USERNAME_XERCES}"
export OS_PASSWORD="${OPENSTACK_PASSWORD_XERCES}"
export OS_AUTH_URL="https://xerces.ericsson.net:5000"
export OS_PROJECT_ID="b62dc8622f87407589de9f7dcec13d25"
export OS_INTERFACE="public"
export OS_PROJECT_NAME="EST_Metal3_CI"
export OS_USER_DOMAIN_NAME="xerces"
export OS_IDENTITY_API_VERSION=3
echo "Cleaning up Private Cloud"
cleanup

#unset openstack variables
unset "${!OS_@}"
