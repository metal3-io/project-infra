# use --ram=8192 for Scenario 2
SERIAL_LOG_PATH="/var/log/libvirt/qemu/bmh-vm-01-serial0.log"

# Define and start the baremetal-e2e network
virsh -c qemu:///system net-define net.xml
virsh -c qemu:///system net-start baremetal-e2e

if ! sudo virsh net-list --all | grep baremetal-e2e; then
    virsh -c qemu:///system net-define "${REPO_ROOT}/hack/e2e/net.xml"
    virsh -c qemu:///system net-start baremetal-e2e
fi

# We need to create veth pair to connect metal3 net (defined above) and kind
# docker subnet. Let us start by creating a docker network with pre-defined
# name for bridge, so that we can configure the veth pair correctly.
# Also assume that if kind net exists, it is created by us.
if ! docker network list | grep kind; then
    # These options are used by kind itself. It uses docker default mtu and
    # generates ipv6 subnet ULA, but we can fix the ULA. Only addition to kind
    # options is the network bridge name.
    docker network create -d=bridge \
        -o com.docker.network.bridge.enable_ip_masquerade=true \
        -o com.docker.network.driver.mtu=1500 \
        -o com.docker.network.bridge.name="kind-bridge" \
        --ipv6 --subnet "fc00:f853:ccd:e793::/64" \
        kind
fi
docker network list

# Next create the veth pair
if ! ip a | grep metalend; then
    sudo ip link add metalend type veth peer name kindend
    sudo ip link set metalend master metal3
    sudo ip link set kindend master kind-bridge
    sudo ip link set metalend up
    sudo ip link set kindend up
fi
ip a

# Then we need to set routing rules as well
if ! sudo iptables -L FORWARD -v -n | grep kind-bridge; then
    sudo iptables -I FORWARD -i kind-bridge -o metal3 -j ACCEPT
    sudo iptables -I FORWARD -i metal3 -o kind-bridge -j ACCEPT
fi
sudo iptables -L FORWARD -n -v

# Start the sushy-emulator container that acts as BMC
docker run --name sushy-tools --rm --network host -d \
  -v /var/run/libvirt:/var/run/libvirt \
  -v "$(pwd)/sushy-tools.conf:/etc/sushy/sushy-emulator.conf" \
  -e SUSHY_EMULATOR_CONFIG=/etc/sushy/sushy-emulator.conf \
  quay.io/metal3-io/sushy-tools:latest sushy-emulator

# Generate a VM definition xml file and then define the VM
virt-install \
  --connect qemu:///system \
  --name bmh-vm-01 \
  --description "Virtualized BareMetalHost" \
  --osinfo=ubuntu-lts-latest \
  --ram=4096 \
  --vcpus=2 \
  --disk size=25 \
  --boot hd,network \
  --import \
  --serial file,path="${SERIAL_LOG_PATH}" \
  --xml "./devices/serial/@type=pty" \
  --xml "./devices/serial/log/@file=${SERIAL_LOG_PATH}" \
  --xml "./devices/serial/log/@append=on" \
  --network network=baremetal-e2e,mac="00:60:2f:31:81:01" \
  --noautoconsole \
  --print-xml > ${QUICK_START_BASE}/bmh-vm-01.xml

virsh define ${QUICK_START_BASE}/bmh-vm-01.xml
