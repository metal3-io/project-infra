ARG GO_VERSION=1.24.9@sha256:8b788ecf5fddb91cd04e532205d6411de68a08b510885bb8fb1c93f54c03f737
FROM docker.io/golang:${GO_VERSION}

# Install additional packages not present in regular golang image
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get install -y libvirt-dev podman \
    && apt-get clean
