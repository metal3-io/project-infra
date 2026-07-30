ARG GO_VERSION=1.26.5@sha256:3aff6657219a4d9c14e27fb1d8976c49c29fddb70ba835014f477e1c70636647
FROM docker.io/golang:${GO_VERSION}

# Install additional packages not present in regular golang image
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get install -y libvirt-dev podman \
    && apt-get clean
