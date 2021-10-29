# Aviatrix Controller AUTH VARS
variable "controller_ip" {
  type    = string
  default = ""
}

variable "username" {
  type    = string
  default = ""
}

variable "password" {
  type    = string
  default = ""
}

variable "region" {
  description = "The AWS region to deploy this module in"
  type        = string
}

variable "account" {
  description = "The AWS account name to use for creating the spokes, as known by the Aviatrix controller"
  type        = string
}

variable "spokes" {
  description = "Map of Names and CIDR ranges to be used for the Spoke VPCs"
  type        = map(string)
}

variable "transit_firenet_cidr" {
  description = "CIDR for transit firenet VPC"
  type        = string
  default     = "10.0.0.0/23"
}

variable "egress_firenet_cidr" {
  description = "CIDR for transit egress VPC"
  type        = string
  default     = "10.0.2.0/23"
}

variable "ingress_cidr" {
  description = "CIDR for ingress VPC"
  type        = string
  default     = "10.100.0.0/24"
}

variable "sharedsvc_cidr" {
  description = "CIDR for shared services VPC"
  type        = string
  default     = "10.0.4.0/24"
}

locals {
}
