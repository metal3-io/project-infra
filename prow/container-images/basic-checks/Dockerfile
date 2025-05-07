ARG GO_VERSION=1.23.8@sha256:a5339982f2e78b38b26ebbee35139854e184a4e90e1516f9f636371e720b727b
FROM docker.io/golang:${GO_VERSION}

# Install additional packages not present in regular golang image
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get install -y libvirt-dev \
    && apt-get clean
