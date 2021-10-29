terraform {
  required_providers {
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 2.20"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "3.63.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">=3.1.0"
    }
  }
  required_version = ">= 0.13"
}
