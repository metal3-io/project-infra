# Create a kind cluster to act as the management cluster
kind create cluster --config kind.yaml

# Install cert-manager. It will be used to manage the certificates for Ironic
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
