ARG GO_VERSION=1.24.4@sha256:10c131810f80a4802c49cab0961bbe18a16f4bb2fb99ef16deaa23e4246fc817
FROM docker.io/golang:${GO_VERSION}

# Install additional packages not present in regular golang image
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get install -y libvirt-dev \
    && apt-get clean
