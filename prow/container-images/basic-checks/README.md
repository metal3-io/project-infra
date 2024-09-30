# Basic-checks image

This Dockerfile is used to create the `quay.io/metal3-io/basic-checks` image,
which is used to run the basic tests in prow.

## Updating image

Make a PR and upon merging, a workflow will build and push the image to Quay to
be used in future test runs. If you switch Golang minor version, update the
workflow file in `.github/workflows/build-images-action.yml` and then update
Prow `config.yaml` accordingly.
