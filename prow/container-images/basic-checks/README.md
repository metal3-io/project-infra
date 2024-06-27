# Basic-checks image

This Dockerfile is used to create the `quay.io/metal3-io/basic-checks` image,
which is used to run the basic tests in prow.

## Steps to build `basic-checks` image

- Determine the go version to use, for e.g. `1.22`
- Login to quay.io `docker login quay.io
- Build the image with `docker build --build-arg GO_VERSION=1.22 -t quay.io/metal3-io/basic-checks:golang-1.22`
- Push the image to quay: `docker push quay.io/metal3-io/basic-checks:golang-1.22`
