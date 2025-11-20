docker run --name dnsmasq --rm -d --net=host --privileged --user 997:994 \
  --env-file dnsmasq.env --entrypoint /bin/rundnsmasq \
  quay.io/metal3-io/ironic
