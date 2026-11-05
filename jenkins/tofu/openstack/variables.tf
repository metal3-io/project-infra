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
 description = "Specific image ID to use (if not specified, will discover latest Rocky by tags)"
 type        = string
 default     = null
}

variable "volume_size" {
 description = "Volume size"
 type        = number
 default     = 10
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

# IMPORTANT: the defaults below are valid in Xerces in ERDC

variable "volume_type" {
 description = "Volume type name"
 type        = string
 default     = "performance"
}

variable "flavor" {
 description = "Flavor name"
 type        = string
 default     = "c4m16-est"
}

variable "external_network" {
 description = "External network name"
 type        = string
 default     = "internet"
}

# IMPORTANT: the defaults below are valid in the project "EST_Metal3_CI"

variable "key" {
 description = "Key pair name"
 type        = string
 default     = "metal3ci-keypair"
}

variable "private_network" {
 description = "Private network name"
 type        = string
 default     = "metal3-ci-net"
}

variable "jumphost_id" {
 description = "Jumphost ID (passed by Ansible based on dynamic cloud inventory)"
 type        = string
 default     = null

 validation {
   condition     = var.jumphost_id != null
   error_message = "Jumphost ID is required"
  }
}

variable "resource_tags" {
  description = "List of tags to apply to resources which support it"
  type        = list
  default     = [
    "jenkins",
    "tf-managed"
  ]
}
