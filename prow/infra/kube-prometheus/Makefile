export CONTAINER_RUNTIME ?= docker

.phony: build

build:
	$(CONTAINER_RUNTIME) run --rm \
		--volume "${PWD}:/workdir:rw,z" \
		--workdir /workdir \
		--entrypoint /workdir/build.sh \
		docker.io/golang:1.23 \
		metal3-kube-prometheus.jsonnet
