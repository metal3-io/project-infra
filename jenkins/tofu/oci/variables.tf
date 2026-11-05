variable "compartment_id" {
 description = "OCI compartment ID (equivalent of an OpenStack project)"
 type        = string
}

variable "availability_domain" {
 description = "OCI availability domain"
 type        = string
 default     = "SdxX:EU-PARIS-1-AD-1"
}

variable "shape" {
 description = "OCI shape"
 type        = string
 default     = "VM.Standard.E4.Flex"
}

variable "ocpus" {
description = "Physical CPU core count (2x vCPU)"
type = number
default = 2
}

variable "memory_gb" {
description = "RAM in gigabytes"
type = number
default = 16
}

variable "host_fqdn" {
 description = "FQDN of application host"
 type        = string
 default     = "ci.apps.test.metal3.io"
}

variable "instance_name" {
 description = "Name of application host instance"
 type        = string
 default     = "jenkins-poc"
}

variable "image_id" {
 description = "Specific image ID to use (if not specified, will discover latest Rocky 10 by name)"
 type        = string
 default     = null
}

variable "web_access_networks" {
 description = "A list of networks in CIDR notation to allow access from"
 type        = list(string)
 default     = ["0.0.0.0/0"]

 validation {
  condition  = alltrue([for network in var.web_access_networks: can(cidrnetmask(network))])
  error_message = "Must be a valid CIDR block."
  }
}

variable "ensure_access" {
 description = "Whether our current address is to be always granted access"
 type        = bool
 default     = false
}

variable "ssh_public_key_file" {
 description = "Fully-qualified path to file containing the SSH public key"
 type        = string
 default     = null
 validation {
  condition  = var.ssh_public_key_file != null
  error_message = "Must provide the name of a public key file."
 }
}

## IMPORTANT: the defaults below are valid in our OCI tenancy

variable "private_network" {
 description = "Private network name"
 type        = string
 default     = "metal3ci-network"
}

variable "resource_tags" {
  description = "List of tags to apply to resources which support it"
  type        = list
  default     = [ "jenkins", "tf-managed" ]
}
