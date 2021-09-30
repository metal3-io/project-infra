#!/bin/bash
# Ensure that the network in the BML has a clean base to work from.

# By default, BIND is installed in the lab, but we use systemd-resolved instead.
sudo killall named

# Sometimes minikube doesn't record which DHCP addresses it has allocated.
# A restart seems to work around this occasional issue.
sudo systemctl restart dnsmasq

# Ensure that DNS resolution is up.
sudo systemctl restart systemd-resolved

# Ensure that network is up.
sudo systemctl restart systemd-networkd
sleep 5
