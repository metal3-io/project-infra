 locals {
   _fqdn_segment_count = length(split(".", var.host_fqdn))
   _domain_index = local._fqdn_segment_count -2
   domain = join(".", slice(split(".", var.host_fqdn), local._domain_index, local._fqdn_segment_count)) # domain.tld from FQDN
   resource_tags = {"tags" = join(", ", concat(var.resource_tags, ["tf-workspace-${terraform.workspace}"]))}
   ip_address = chomp(data.http.myip.response_body)
   ip_address_allowed = anytrue([for network in var.web_access_networks: cidrcontains(network, local.ip_address)])
   web_access_networks = alltrue([!local.ip_address_allowed, var.ensure_access]) ? concat(var.web_access_networks, formatlist("%s/32", local.ip_address)) : var.web_access_networks
   last_discovered_rocky_image = data.oci_core_images.rocky == null ? null : element(data.oci_core_images.rocky.images, -1)
   boot_image = var.image_id == null ? local.last_discovered_rocky_image.id : var.image_id
   private_network = element(data.oci_core_vcns.private.virtual_networks, -1)
   private_subnet = element(data.oci_core_subnets.private.subnets, -1)
   ssh_public_key = file(var.ssh_public_key_file)
 }

# lacking a tagging system for now, we take the latest image that has a name starting with "Rocky-10-"
data "oci_core_images" "rocky" {
  compartment_id = var.compartment_id
  state = "AVAILABLE"
  sort_by = "TIMECREATED"
  sort_order = "ASC"
  filter {
    name   = "display_name"
    values = ["^Rocky-10-.*$"]
    regex  = true
  }
  lifecycle {
    enabled = var.image_id == null
  }
}

data "oci_core_vcns" "private" {
  compartment_id = var.compartment_id
  state = "AVAILABLE"
  display_name = var.private_network
}

data "oci_core_subnets" "private" {
  compartment_id = var.compartment_id
  vcn_id         = local.private_network.id
  state = "AVAILABLE"
}

 data "http" "myip" {
   url = "https://ipv4.icanhazip.com"
 }

resource "oci_core_network_security_group" "access" {
  compartment_id = var.compartment_id
  vcn_id         = local.private_network.id
  freeform_tags  = local.resource_tags
  display_name   = var.instance_name
}

resource "oci_core_network_security_group_security_rule" "ssh" {
  network_security_group_id = oci_core_network_security_group.access.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "129.192.82.109/32" # CI jumphost in Xerces instead of "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      max = 22
      min = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "https" {
  network_security_group_id = oci_core_network_security_group.access.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  for_each                  = toset(local.web_access_networks)
  source                    = each.key
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      max = 443
      min = 443
    }
  }
}

resource "oci_core_instance" "server" {
  availability_domain   = var.availability_domain
  compartment_id        = var.compartment_id
  display_name          = var.instance_name
  shape                 = var.shape
  shape_config {
    ocpus               = var.ocpus # 2x vCPU on x86
    memory_in_gbs       = var.memory_gb
  }
  source_details {
    source_id           = local.boot_image
    source_type         = "image"
  }
  create_vnic_details {
    subnet_id           = local.private_subnet.id
    nsg_ids             = [resource.oci_core_network_security_group.access.id]
  }
  metadata              = {
    ssh_authorized_keys = local.ssh_public_key
  }
  freeform_tags         = local.resource_tags
}

output "external_address" {
  value = resource.oci_core_instance.server.public_ip
}

data "netlify_dns_zone" "domain" {
  name = local.domain
}

resource "netlify_dns_record" "host_fqdn" {
  type     = "A"
  zone_id  = data.netlify_dns_zone.domain.id
  hostname = var.host_fqdn
  value    = resource.oci_core_instance.server.public_ip
}
