ARG GO_VERSION=1.22
FROM docker.io/golang:${GO_VERSION}

# Install packages
RUN apt-get update \
    && apt-get install -y libvirt-dev \
    && apt-get clean
