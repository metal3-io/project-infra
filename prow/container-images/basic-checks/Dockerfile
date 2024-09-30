ARG GO_VERSION=1.22.7@sha256:192683db8982323952988c7b86c098ee7ecc6cbeb202bf7c113ff9be5358367c
FROM docker.io/golang:${GO_VERSION}

# Install additional packages not present in regular golang image
RUN apt-get update \
    && apt-get install -y libvirt-dev \
    && apt-get clean
