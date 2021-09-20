.phony: update-config update-plugins update-labels validate

update-config:
	kubectl create configmap config -n prow --from-file=config.yaml=config/config.yaml --dry-run=client -o yaml | kubectl replace configmap -n prow config -f -

update-plugins:
	kubectl create configmap plugins -n prow --from-file=plugins.yaml=config/plugins.yaml --dry-run=client -o yaml | kubectl replace configmap -n prow plugins -f -

update-labels:
	kubectl create configmap label-config -n prow --from-file=labels.yaml=labels.yaml --dry-run=client -o yaml | kubectl replace configmap -n prow label-config -f -

validate:
	podman run --rm \
		--volume "${PWD}:/workdir:ro,z" \
		--entrypoint /checkconfig \
		gcr.io/k8s-prow/checkconfig:v20210409-985ef5e721 \
		--config-path /workdir/config/config.yaml \
		--plugin-config /workdir/config/plugins.yaml \
		--strict
