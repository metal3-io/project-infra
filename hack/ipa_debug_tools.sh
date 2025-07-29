#!/usr/bin/env bash

# The path to the directory that holds this script
CURRENT_SCRIPT_DIR="$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")"

# This ceates a minimal set up in /tmp/debug-initramfs directory for
# comparing built ipa initramfs the master ipa initramfs.
set_up_debug_dirs() {
    # Export DISABLE_UPLOAD, ENABLE_BOOTSTRAP_TEST, TEST_IN_CI to allow local
    # test run.
    export DISABLE_UPLOAD="true"
    export ENABLE_BOOTSTRAP_TEST="false"
    export TEST_IN_CI="false"

    # Build ipa with build_ipa.sh
    cd "$CURRENT_SCRIPT_DIR/../jenkins/scripts/dynamic_worker_workflow" || exit
    if [[ ! -x ./build_ipa.sh ]]; then
        echo "Error: build_ipa.sh not found or not executable in $(pwd)"
        exit 1
    fi
    ./build_ipa.sh

    # Even if build_ipa.sh exits with error this script can continue as long as
    # /tmp/dib/ironic-python-agent.initramfs has been created
    if [[ ! -f /tmp/dib/ironic-python-agent.initramfs ]]; then
        exit 1
    fi

    # Unzip ironic-python-agent.initramfs
    sudo mkdir -p /tmp/debug-initramfs/build-ipa-initramfs
    sudo cp /tmp/dib/ironic-python-agent.initramfs /tmp/debug-initramfs/
    cd /tmp/debug-initramfs/build-ipa-initramfs || exit
    gunzip -c ../ironic-python-agent.initramfs | sudo cpio -id

    # Get master ironic-python-agent.initramfs and unzip
    sudo mkdir -p /tmp/debug-initramfs/master-ipa-initramfs
    cd /tmp/debug-initramfs || exit
    sudo wget https://tarballs.opendev.org/openstack/ironic-python-agent/dib/ipa-centos9-master.tar.gz
    sudo tar -xzf ipa-centos9-master.tar.gz
    cd master-ipa-initramfs || exit
    gunzip -c ../ipa-centos9-master.initramfs | sudo cpio -id
}

# -----------------------------------------------------------------------------
# compare_dir_sizes <relative_path> [base_dir1] [base_dir2]
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
# - [base_dir1]:     First base directory (default: /tmp/debug-initramfs/build-ipa-initramfs)
# - [base_dir2]:     Second base directory (default: /tmp/debug-initramfs/master-ipa-initramfs)
#
# The function prints a table of entries, their sizes in both directories,
# and the size difference. It also lists files only present in one directory.
# -----------------------------------------------------------------------------
compare_dir_sizes() {
    path="${1:-}"
    basedir1="${2:-/tmp/debug-initramfs/build-ipa-initramfs}"
    basedir2="${3:-/tmp/debug-initramfs/master-ipa-initramfs}"

    dir1="${basedir1}/${path}"
    dir2="${basedir2}/${path}"
    
    # Color codes
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
    BOLD='\033[1m'
    
    echo -e "${CYAN}📊 Comparing directories:${NC}"
    echo -e "  ${BLUE}🏗️  Build IPA:${NC} ${dir1}"
    echo -e "  ${GREEN}🎯 Master IPA:${NC} ${dir2}"
    echo ""
    
    # Print table header
    printf "${BOLD}%-40s %-22s %-22s %-22s${NC}\n" "Directory/File" "🏗️  Build" "🎯 Master" "📏 Diff"
    echo "======================================================================================================="

    tmpfile=$(mktemp)
    checked=0
    skipped=0

    # Compare entries present in both directories
    find "${dir1}" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort > /tmp/dir1_list
    find "${dir2}" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort > /tmp/dir2_list
    comm -12 /tmp/dir1_list /tmp/dir2_list | while IFS= read -r name; do
        # Get size in bytes for each entry
        bsize=$(du -sb "${dir1}/${name}" 2>/dev/null | cut -f1)
        isize=$(du -sb "${dir2}/${name}" 2>/dev/null | cut -f1)
        # Calculate absolute difference
        diff=$(( bsize > isize ? bsize - isize : isize - bsize ))
        echo -e "${name}\t${bsize}\t${isize}\t${diff}"
    done | sort -k4,4nr > "${tmpfile}"

    # Print entries with size differences
    while IFS=$'\t' read -r name bsize isize diff; do
        checked=$((checked+1))
        if [[ "${diff}" -eq 0 ]]; then
            skipped=$((skipped+1))
            continue
        fi
        
        # Color code based on size difference magnitude
        if [[ "${diff}" -gt 10485760 ]]; then  # > 10MB
            diff_color="${RED}"
            icon="🔴"
        elif [[ "${diff}" -gt 1048576 ]]; then  # > 1MB
            diff_color="${YELLOW}"
            icon="🟡"
        else
            diff_color="${GREEN}"
            icon="🟢"
        fi
        
        printf "%-40s ${BLUE}%-22s${NC} ${GREEN}%-22s${NC} ${diff_color}%s %-21s${NC}\n" \
            "${name}" \
            "$(numfmt --to=iec "${bsize}")" \
            "$(numfmt --to=iec "${isize}")" \
            "${icon}" \
            "$(numfmt --to=iec "${diff}")"
    done < "$tmpfile"

    echo -e "\n${PURPLE}📈 Summary:${NC} Checked ${BOLD}${checked}${NC} common entries, skipped ${BOLD}${skipped}${NC} identical sizes."
    echo "======================================================================================================="

    rm -f "${tmpfile}"

    # List files only in dir1
    echo -e "\n${BLUE}🏗️  Only in Build IPA (${dir1}):${NC}"
    echo "-------------------------------------------------------------------------------------------------------"
    comm -23 /tmp/dir1_list /tmp/dir2_list | while IFS= read -r name; do
        bsize=$(du -sb "${dir1}/${name}" 2>/dev/null | cut -f1)
        echo -e "${bsize}\t${name}"
    done | sort -k1,1nr | while IFS=$'\t' read -r bsize name; do
        printf "${BLUE}%-40s %-22s${NC}\n" "➕ ${name}" "$(numfmt --to=iec "${bsize}")"
    done

    echo "======================================================================================================="

    # List files only in dir2
    echo -e "\n${GREEN}🎯 Only in Master IPA (${dir2}):${NC}"
    echo "-------------------------------------------------------------------------------------------------------"
    comm -13 /tmp/dir1_list /tmp/dir2_list | while IFS= read -r name; do
        isize=$(du -sb "${dir2}/${name}" 2>/dev/null | cut -f1)
        echo -e "${isize}\t${name}"
    done | sort -k1,1nr | while IFS=$'\t' read -r isize name; do
        printf "${GREEN}%-40s %-22s${NC}\n" "➕ ${name}" "$(numfmt --to=iec "${isize}")"
    done

    # Print some empty lines for clarity
    echo ""
    echo ""
    echo ""
    
    # Remove temporary dir lists
    rm /tmp/dir1_list /tmp/dir2_list
}

# Print a rpm package list. The print omits packages that are identical in both
#the built ipa and master.
# Check if packages are a part of CentOS Stream in https://pkgs.org
compare_rpm_packages() {
    basedir1="${1:-/tmp/debug-initramfs/build-ipa-initramfs}" 
    basedir2="${2:-/tmp/debug-initramfs/master-ipa-initramfs}"
    compfile1="/tmp/build-ipa-rpm.txt"
    compfile2="/tmp/master-ipa-rpm.txt"

    sudo chroot "${basedir1}" rpm -qa | sort > "${compfile1}"
    sudo chroot "${basedir2}" rpm -qa | sort > "${compfile2}"

    common_count=$(comm -12 "${compfile1}" "${compfile2}" | wc -l)
    echo -e "\nNumber of common packages: ${common_count}\n"
    # Extract base package names and join for fuzzy matching
    awk -F'-[0-9]' '{print $1}' "${compfile1}" | sort > /tmp/build-ipa-base.txt
    awk -F'-[0-9]' '{print $1}' "${compfile2}" | sort > /tmp/master-ipa-base.txt

    printf "%-65s | %-65s\n" "In ${basedir1}" "In ${basedir2}"
    printf -- "----------------------------------------------------------------------------------------------------------------------------------\n"

    join -a1 -a2 -e '' -o 1.1,2.1 /tmp/build-ipa-base.txt /tmp/master-ipa-base.txt | \
    while IFS=' ' read -r left right; do
        # Find the full package lines for each base name
        lfull=$(grep -m1 "^${left}-" "${compfile1}" || echo "")
        rfull=$(grep -m1 "^${right}-" "${compfile2}" || echo "")
        # Skip printing if both lines are non-empty and exactly the same
        if [[ -n "${lfull}" && "${lfull}" == "${rfull}" ]]; then
            continue
        fi
        printf "%-65s | %-65s\n" "${lfull}" "${rfull}"
    done

    sudo rm -f "${compfile1}" "${compfile2}" /tmp/build-ipa-base.txt /tmp/master-ipa-base.txt
}

# After debugging and comparison operations, temporary directories can be cleaned up.
# Usage:
#   ./ipa_debug_tools.sh clean_up_debug_dirs
# -----------------------------------------------------------------------------
clean_up_debug_dirs() {
    # Clean up debug directories
    sudo rm -rf /tmp/debug-initramfs
}

# Allow calling functions
# -----------------------------------------------------------------------------
function_name="$1"
shift

# Check if function exists and call it
if declare -f "$function_name" > /dev/null; then
    "$function_name" "$@"
else
    echo "Error: Function '$function_name' not found"
    echo "Available functions: set_up_debug_dirs, compare_dir_sizes, compare_rpm_packages, clean_up_debug_dirs"
    exit 1
fi
