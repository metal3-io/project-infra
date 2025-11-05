# Delete the management cluster.
kind delete cluster

# Stop DHCP and image servers. They are automatically removed when stopped.
docker stop dnsmasq
docker stop image-server

# Cleanup the sushy-tools container and the VM. (For virtual-lab setup)
docker stop sushy-tools

virsh -c qemu:///system destroy --domain bmh-vm-01
virsh -c qemu:///system undefine --domain bmh-vm-01 --remove-all-storage --nvram

virsh -c qemu:///system net-destroy baremetal-e2e
virsh -c qemu:///system net-undefine baremetal-e2e

export QUICK_START_BASE=${QUICK_START_BASE:="$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")"}
rm -rf "${QUICK_START_BASE}/bmh-vm-01.xml"