ARG GO_VERSION=1.25.6@sha256:06d1251c59a75761ce4ebc8b299030576233d7437c886a68b43464bad62d4bb1
FROM docker.io/golang:${GO_VERSION}

# Install additional packages not present in regular golang image
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get install -y libvirt-dev podman \
    && apt-get clean
