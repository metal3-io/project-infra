# NOTE: required environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, NETLIFY_API_TOKEN (to be populated by Ansible from 1pw)

terraform {
required_version = ">= 1.11.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4.0"
    }
    netlify = {
      source = "netlify/netlify"
      version = "0.4.1"
    }
    http = {
      source = "hashicorp/http"
      version = "3.5.0"
    }
  }
  backend "s3" {
    bucket = "tofu"
    key    = "jenkins.tfstate"
    use_lockfile = true
    lock_tags = {
      "object:type": "lock"
    }
    region = "RegionOne"
    skip_region_validation = true
    skip_credentials_validation = true
    use_path_style = true
    endpoints = {
      s3 = "https://xerces.ericsson.net:7480"
    }
  }
}
