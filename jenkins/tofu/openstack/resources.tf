locals {
  _fqdn_segment_count = length(split(".", var.host_fqdn))
  _domain_index = local._fqdn_segment_count -2
  domain = join(".", slice(split(".", var.host_fqdn), local._domain_index, local._fqdn_segment_count)) # domain.tld from FQDN
  resource_tags = concat(var.resource_tags, ["tf-workspace-${terraform.workspace}"])
  ip_address = chomp(data.http.myip.response_body)
  ip_address_allowed = anytrue([for network in var.web_access_networks: cidrcontains(network, local.ip_address)])
  web_access_networks = alltrue([!local.ip_address_allowed, var.ensure_access]) ? concat(var.web_access_networks, formatlist("%s/32", local.ip_address)) : var.web_access_networks
}

data "openstack_images_image_v2" "boot_image" {
  tags = [
    "rocky",
    "v10",
    "latest"
  ]
  lifecycle {
    enabled = var.image_id == null
  }
}

data "openstack_networking_network_v2" "private" {
  name = var.private_network
}

data "openstack_compute_instance_v2" "jumphost" {
  id = var.jumphost_id
}

data "http" "myip" {
  url = "https://ipv4.icanhazip.com"
}

resource "openstack_blockstorage_volume_v3" "boot" {
  name = format("%s-boot", var.instance_name)
  image_id = var.image_id == null ? data.openstack_images_image_v2.boot_image.id : var.image_id
  size = var.volume_size
  volume_type = var.volume_type
}

resource "openstack_networking_secgroup_v2" "access" {
  name        = var.instance_name
  description = "web, ssh"
  tags = local.resource_tags
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  description = "SSH"
  direction = "ingress"
  ethertype = "IPv4"
  port_range_max = 22
  port_range_min = 22
  protocol = "tcp"
  remote_ip_prefix = format("%s/32", data.openstack_compute_instance_v2.jumphost.network[0].fixed_ip_v4)
  security_group_id = openstack_networking_secgroup_v2.access.id
}

resource "openstack_networking_secgroup_rule_v2" "https" {
  description       = "HTTPS"
  direction         = "ingress"
  ethertype         = "IPv4"
  port_range_max    = 443
  port_range_min    = 443
  protocol          = "tcp"
  remote_group_id   = null
  for_each          = toset(local.web_access_networks)
  remote_ip_prefix  = each.key
  security_group_id = openstack_networking_secgroup_v2.access.id
}

resource "openstack_compute_instance_v2" "server" {
  flavor_name = var.flavor
  key_pair = var.key
  name = var.instance_name
  security_groups = [openstack_networking_secgroup_v2.access.name]
  block_device {
    boot_index = 0
    delete_on_termination = false
    destination_type = "volume"
    source_type = "volume"
    uuid = openstack_blockstorage_volume_v3.boot.id
  }
  network {
    uuid = data.openstack_networking_network_v2.private.id
  }
  tags = local.resource_tags
}

resource "openstack_networking_floatingip_v2" "external" {
  pool = var.external_network
  tags = local.resource_tags
}

output "internal_address" {
  value = openstack_compute_instance_v2.server.network.0.fixed_ip_v4
}

data "openstack_networking_port_v2" "private" {
  device_id  = openstack_compute_instance_v2.server.id
  network_id = openstack_compute_instance_v2.server.network.0.uuid
}

resource "openstack_networking_floatingip_associate_v2" "access" {
  floating_ip = openstack_networking_floatingip_v2.external.address
  port_id = data.openstack_networking_port_v2.private.id
}

data "netlify_dns_zone" "domain" {
  name = local.domain
}

resource "netlify_dns_record" "host_fqdn" {
  type     = "A"
  zone_id  = data.netlify_dns_zone.domain.id
  hostname = var.host_fqdn
  value    = openstack_networking_floatingip_v2.external.address
}
