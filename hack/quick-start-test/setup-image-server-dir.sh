# Create a directory to hold the disk images:
mkdir ${QUICK_START_BASE}/disk-images

# Download images to use for testing (pick those that you want):
pushd ${QUICK_START_BASE}/disk-images
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
wget https://cloud-images.ubuntu.com/noble/current/SHA256SUMS
sha256sum --ignore-missing -c SHA256SUMS
wget https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2
wget https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2.SHA256SUM
sha256sum -c CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2.SHA256SUM
wget https://artifactory.nordix.org/artifactory/metal3/images/k8s_v1.34.0/CENTOS_9_NODE_IMAGE_K8S_v1.34.0.qcow2
sha256sum CENTOS_9_NODE_IMAGE_K8S_v1.34.0.qcow2
wget https://tarballs.opendev.org/openstack/ironic-python-agent/dib/ipa-centos9-master.tar.gz
popd
