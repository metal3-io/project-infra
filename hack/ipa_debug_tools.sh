#!/usr/bin/env bash
set -eu

# The path to the directory that holds this script
CURRENT_SCRIPT_DIR="$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")"
BASE_DEBUG_DIR="/tmp/debug-initramfs"
mkdir -p ${BASE_DEBUG_DIR}
BASE_HELPER_FILE_DIR=$(sudo mktemp -dp "${BASE_DEBUG_DIR}")

# Fix permissions so current user can create temp files
sudo chown "${USER}:$(id -gn)" "${BASE_HELPER_FILE_DIR}"

# Set up cleanup trap to run when script exits
trap clean_up_debug_helpers EXIT

# set_up_debug_dirs [file] [url]
#
# This creates a minimal set up in /tmp/debug-initramfs directory for
# comparing built ipa initramfs the master ipa initramfs.
#
# Usage examples:
#   ./ipa_debug_tools.sh set_up_debug_dirs
#   ./ipa_debug_tools.sh set_up_debug_dirs ipa-centos9-master.tar.gz
#   ./ipa_debug_tools.sh set_up_debug_dirs ipa-centos9-master.tar.gz https://tarballs.opendev.org/openstack/ironic-python-agent/dib/
#
# - [file]: Name of tar file to be downloaded [default: ipa-centos9-master.tar.gz]
# - [url]: Url to ironic python agent tarball archive [default: https://tarballs.opendev.org/openstack/ironic-python-agent/dib/]
#
set_up_debug_dirs() {
    file_name="${1:-ipa-centos9-master.tar.gz}"
    url="${2:-https://tarballs.opendev.org/openstack/ironic-python-agent/dib/}"
    full_path="${url}${file_name}"
    file_base_name=$(echo "${file_name}"| cut -d'.' -f 1)

    clean_up_debug_dirs

    # Export DISABLE_UPLOAD, ENABLE_BOOTSTRAP_TEST, TEST_IN_CI to allow local
    # test run.
    export DISABLE_UPLOAD="true"
    export ENABLE_BOOTSTRAP_TEST="false"
    export TEST_IN_CI="false"

    # Build ipa with build_ipa.sh. Search for the script in a path that is
    # relative to this file's location. 
    cd "${CURRENT_SCRIPT_DIR}/../jenkins/scripts/dynamic_worker_workflow"
    if [[ ! -x ./build_ipa.sh ]]; then
        echo "Error: build_ipa.sh not found"
        exit 1
    fi
    
    if ! ./build_ipa.sh; then
        echo "build_ipa.sh failed, will check for artifact..."
    fi

    # Even if build_ipa.sh exits with error this script can continue as long as
    # /tmp/dib/ironic-python-agent.initramfs has been created
    if [[ ! -f /tmp/dib/ironic-python-agent.initramfs ]]; then
        echo "Required file '/tmp/dib/ironic-python-agent.initramfs' not created, exiting."
        exit 1
    fi

    # Unzip ironic-python-agent.initramfs
    sudo mkdir -p "${BASE_DEBUG_DIR}/build-ipa-initramfs"
    sudo cp /tmp/dib/ironic-python-agent.initramfs "${BASE_DEBUG_DIR}/"
    cd "${BASE_DEBUG_DIR}/build-ipa-initramfs"
    gunzip -c ../ironic-python-agent.initramfs | sudo cpio -id

    # Get master ironic-python-agent.initramfs and unzip
    sudo mkdir -p "${BASE_DEBUG_DIR}/master-ipa-initramfs"
    cd "${BASE_DEBUG_DIR}"
    sudo wget "${full_path}"
    sudo tar -xzf "${file_name}"
    cd master-ipa-initramfs
    gunzip -c "../${file_base_name}.initramfs" | sudo cpio -id
}

# -----------------------------------------------------------------------------
# compare_dir_sizes <relative_path> [base_build_dir] [base_master_dir]
#
# Compares the sizes of files and directories at the given <relative_path>
# inside two extracted initramfs directories (or any two directories).
#
# Usage examples:
#   ./ipa_debug_tools.sh compare_dir_sizes
#   ./ipa_debug_tools.sh compare_dir_sizes usr
#   ./ipa_debug_tools.sh compare_dir_sizes usr/lib ~/ipa-build-initramfs ~/ipa-initramfs
#   ./ipa_debug_tools.sh compare_dir_sizes . ~/ipa-build-initramfs ~/ipa-initramfs
#
# - <relative_path>: Path inside the compared directories (e.g., usr, usr/lib)
# - [base_build_dir]:     First base directory (default: /tmp/debug-initramfs/build-ipa-initramfs)
# - [base_master_dir]:     Second base directory (default: /tmp/debug-initramfs/master-ipa-initramfs)
#
# The function prints a table of entries, their sizes in both directories,
# and the size difference. It also lists files only present in one directory.
# -----------------------------------------------------------------------------
compare_dir_sizes() {
    path="${1:-}"
    build_dir_base="${2:-${BASE_DEBUG_DIR}/build-ipa-initramfs}"
    master_dir_base="${3:-${BASE_DEBUG_DIR}/master-ipa-initramfs}"

    build_dir="${build_dir_base}/${path}"
    master_dir="${master_dir_base}/${path}"
    
    # Color codes
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
    BOLD='\033[1m'
    
    echo -e "${CYAN}Comparing directories:${NC}"
    echo -e "  ${BLUE}Build IPA:${NC} ${build_dir}"
    echo -e "  ${GREEN}Master IPA:${NC} ${master_dir}"
    echo ""
    
    # Print table header
    printf "${BOLD}%-40s %-22s %-22s %-22s${NC}\n" "Directory/File" "Build" "Master" "Diff"
    echo "======================================================================================================="

    tmpfile=$(mktemp -p "${BASE_HELPER_FILE_DIR}")
    build_dir_list=$(mktemp -p "${BASE_HELPER_FILE_DIR}")
    master_dir_list=$(mktemp -p "${BASE_HELPER_FILE_DIR}")
    checked=0
    skipped=0

    # Compare entries present in both directories
    find "${build_dir}" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort > "${build_dir_list}"
    find "${master_dir}" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort > "${master_dir_list}"
    comm -12 "${build_dir_list}" "${master_dir_list}" | while IFS= read -r name; do
        # Get size in bytes for each entry
        bsize=$(du -sb "${build_dir}/${name}" 2>/dev/null | cut -f1)
        isize=$(du -sb "${master_dir}/${name}" 2>/dev/null | cut -f1)
        # Calculate absolute difference
        diff=$(( bsize > isize ? bsize - isize : isize - bsize ))
        echo -e "${name}\t${bsize}\t${isize}\t${diff}"
    done | sort -k4,4nr > "${tmpfile}"

    # Print entries with size differences
    while IFS=$'\t' read -r name bsize isize diff; do
        checked=$((checked + 1))
        if [[ "${diff}" -eq 0 ]]; then
            skipped=$((skipped + 1))
            continue
        fi
        
        # Color code based on size difference magnitude
        if [[ "${diff}" -gt 10485760 ]]; then  # > 10MB
            diff_color="${RED}"
        elif [[ "${diff}" -gt 1048576 ]]; then  # > 1MB
            diff_color="${YELLOW}"
        else
            diff_color="${GREEN}"
        fi
        
        printf "%-40s ${BLUE}%-22s${NC} ${GREEN}%-22s${NC} ${diff_color}%-21s${NC}\n" \
            "${name}" \
            "$(numfmt --to=iec "${bsize}")" \
            "$(numfmt --to=iec "${isize}")" \
            "$(numfmt --to=iec "${diff}")"
    done < "${tmpfile}"

    echo -e "\n${PURPLE}Summary:${NC} Checked ${BOLD}${checked}${NC} common entries, skipped ${BOLD}${skipped}${NC} identical sizes."
    echo "======================================================================================================="

    # List files only in build_dir
    echo -e "\n${BLUE}Only in Build IPA (${build_dir}):${NC}"
    echo "-------------------------------------------------------------------------------------------------------"
    comm -23 "${build_dir_list}" "${master_dir_list}" | while IFS= read -r name; do
        bsize=$(du -sb "${build_dir}/${name}" 2>/dev/null | cut -f1)
        echo -e "${bsize}\t${name}"
    done | sort -k1,1nr | while IFS=$'\t' read -r bsize name; do
        printf "${BLUE}%-40s %-22s${NC}\n" "${name}" "$(numfmt --to=iec "${bsize}")"
    done

    echo "======================================================================================================="

    # List files only in master_dir
    echo -e "\n${GREEN}Only in Master IPA (${master_dir}):${NC}"
    echo "-------------------------------------------------------------------------------------------------------"
    comm -13 "${build_dir_list}" "${master_dir_list}" | while IFS= read -r name; do
        isize=$(du -sb "${master_dir}/${name}" 2>/dev/null | cut -f1)
        echo -e "${isize}\t${name}"
    done | sort -k1,1nr | while IFS=$'\t' read -r isize name; do
        printf "${GREEN}%-40s %-22s${NC}\n" "${name}" "$(numfmt --to=iec "${isize}")"
    done

    # Print some empty lines for clarity
    echo -e "\n\n\n"
}

# Print a rpm package list. The print omits packages that are identical in both
# the built ipa and master.
# Check if packages are a part of CentOS Stream in https://pkgs.org
compare_rpm_packages() {
    build_dir="${1:-${BASE_DEBUG_DIR}/build-ipa-initramfs}" 
    master_dir="${2:-${BASE_DEBUG_DIR}/master-ipa-initramfs}"
    build_rpm_list=$(mktemp -p "${BASE_HELPER_FILE_DIR}")
    master_rpm_list=$(mktemp -p "${BASE_HELPER_FILE_DIR}")
    build_rpm_list_name_bases=$(mktemp -p "${BASE_HELPER_FILE_DIR}")
    master_rpm_list_name_bases=$(mktemp -p "${BASE_HELPER_FILE_DIR}")

    sudo chroot "${build_dir}" rpm -qa | sort > "${build_rpm_list}"
    sudo chroot "${master_dir}" rpm -qa | sort > "${master_rpm_list}"

    common_count=$(comm -12 "${build_rpm_list}" "${master_rpm_list}" | wc -l)
    echo -e "\nNumber of common packages: ${common_count}\n"
    # Extract base package names and join for fuzzy matching
    awk -F'-[0-9]' '{print $1}' "${build_rpm_list}" | sort > "${build_rpm_list_name_bases}"
    awk -F'-[0-9]' '{print $1}' "${master_rpm_list}" | sort > "${master_rpm_list_name_bases}"

    printf "%-65s | %-65s\n" "In ${build_dir}" "In ${master_dir}"
    printf -- "----------------------------------------------------------------------------------------------------------------------------------\n"

    join -a1 -a2 -e '' -o 1.1,2.1 "${build_rpm_list_name_bases}" "${master_rpm_list_name_bases}" | \
    while IFS=' ' read -r left right; do
        # Find the full package lines for each base name
        lfull=$(grep -m1 "^${left}-" "${build_rpm_list}" || echo "")
        rfull=$(grep -m1 "^${right}-" "${master_rpm_list}" || echo "")
        # Skip printing if both lines are non-empty and exactly the same
        if [[ -n "${lfull}" ]] && [[ "${lfull}" == "${rfull}" ]]; then
            continue
        fi
        printf "%-65s | %-65s\n" "${lfull}" "${rfull}"
    done
}

# After debugging and comparison operations, temporary directories can be cleaned up.
# This function removes the build and master filesystems. If this operation is run
# the set_up_debug_dirs needs to be run again to create the comparable filesystems.
# Usage:
#   ./ipa_debug_tools.sh clean_up_debug_dirs
# -----------------------------------------------------------------------------
clean_up_debug_dirs() {
    # Clean up debug directories
    sudo rm -rf "${BASE_DEBUG_DIR}" /tmp/dib ipa-file-injector.service 2> /dev/null
}

# Clean up all helper temp files.
clean_up_debug_helpers() {
    sudo rm -rf "${BASE_HELPER_FILE_DIR}" 2> /dev/null
}

# Allow calling functions from command line
# -----------------------------------------------------------------------------
# Display usage information
usage() {
    cat << EOF
Usage: ${0} <command> [options]

COMMANDS:
    set_up_debug_dirs [file] [url]
        Set up debug directories for comparing IPA initramfs
        
        Options:
            file    Name of tar file to download (default: ipa-centos9-master.tar.gz)
            url     URL to tarball archive (default: https://tarballs.opendev.org/openstack/ironic-python-agent/dib/)

    compare_dir_sizes [relative_path] [base_build_dir] [base_master_dir]
        Compare sizes of files and directories
        
        Options:
            relative_path    Path inside compared directories (default: "")
            base_build_dir   First base directory (default: /tmp/debug-initramfs/build-ipa-initramfs)
            base_master_dir  Second base directory (default: /tmp/debug-initramfs/master-ipa-initramfs)

    compare_rpm_packages [build_dir] [master_dir]
        Compare RPM packages between two directories
        
        Options:
            build_dir    Build directory (default: /tmp/debug-initramfs/build-ipa-initramfs)
            master_dir   Master directory (default: /tmp/debug-initramfs/master-ipa-initramfs)

    clean_up_debug_dirs
        Clean up all debug directories and temporary files

    help, -h, --help
        Show this help message

    EXAMPLE 
        ./ipa_debug_tools.sh set_up_debug_dirs
        ./ipa_debug_tools.sh compare_dir_sizes
        ./ipa_debug_tools.sh compare_rpm_packages
        ./ipa_debug_tools.sh clean_up_debug_dirs

EOF
}

# Argument parsing
main() {
    # Check if no arguments provided
    if [[ ${#} -eq 0 ]]; then
        echo "Error: Command missing"
        echo ""
        echo "Available commands: set_up_debug_dirs, compare_dir_sizes, compare_rpm_packages, clean_up_debug_dirs"
        echo "Use '${0} help' for detailed usage information"
        exit 1
    fi

    local command="${1}"
    shift

    case "${command}" in
        help|-h|--help)
            usage
            exit 0
            ;;
        set_up_debug_dirs|compare_dir_sizes|compare_rpm_packages|clean_up_debug_dirs)
            # Check if function exists and call it
            if declare -f "${command}" > /dev/null; then
                "${command}" "${@}"
            else
                echo "Error: Function '${command}' not implemented"
                exit 1
            fi
            ;;
        *)
            echo "Error: Unknown command '${command}'"
            echo ""
            echo "Available commands: set_up_debug_dirs, compare_dir_sizes, compare_rpm_packages, clean_up_debug_dirs"
            echo "Use '${0} help' for detailed usage information"
            exit 1
            ;;
    esac
}

main "${@}"
