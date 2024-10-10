ARG GO_VERSION=1.22.8@sha256:b274ff14d8eb9309b61b1a45333bf0559a554ebcf6732fa2012dbed9b01ea56f
FROM docker.io/golang:${GO_VERSION}

# Install additional packages not present in regular golang image
RUN apt-get update \
    && apt-get install -y libvirt-dev \
    && apt-get clean
