ARG GO_VERSION=1.23.7@sha256:1acb493b9f9dfdfe705042ce09e8ded908ce4fb342405ecf3ca61ce7f3b168c7
FROM docker.io/golang:${GO_VERSION}

# Install additional packages not present in regular golang image
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get install -y libvirt-dev \
    && apt-get clean
