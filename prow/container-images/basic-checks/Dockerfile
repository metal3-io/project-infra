ARG GO_VERSION=1.24.8@sha256:dd80b4158d9c4ca750687719d1a4b79ec9f78f19c4b87b53b73d552ceccfb7a8
FROM docker.io/golang:${GO_VERSION}

# Install additional packages not present in regular golang image
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get install -y libvirt-dev podman \
    && apt-get clean
