ARG GO_VERSION=1.23.3@sha256:73f06be4578c9987ce560087e2e2ea6485fb605e3910542cadd8fa09fc5f3e31
FROM docker.io/golang:${GO_VERSION}

# Install additional packages not present in regular golang image
RUN apt-get update \
    && apt-get install -y libvirt-dev \
    && apt-get clean
