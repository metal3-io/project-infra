ARG GO_VERSION=1.24.10@sha256:7b13449f08287fdb53114d65bdf20eb3965e4e54997903b5cb9477df0ea37c12
FROM docker.io/golang:${GO_VERSION}

# Install additional packages not present in regular golang image
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get install -y libvirt-dev podman \
    && apt-get clean
