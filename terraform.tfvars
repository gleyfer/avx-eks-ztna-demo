// Note: best to set controller_ip, username, password for Aviatrix Controller
// as environment variables: https://registry.terraform.io/providers/AviatrixSystems/aviatrix/latest/docs#environment-variables

// Modify below as needed:
region                   = "us-west-2"
account                  = "Account" # Replace with your AWS Access Account in Controller
transit_firenet_cidr     = "10.0.0.0/23"
egress_firenet_cidr      = "10.0.2.0/23"
sharedsvc_cidr           = "10.0.4.0/24"
ingress_cidr             = "10.100.0.0/23"
spokes                   = { "Dev" = "10.1.0.0/16", "Prod" = "10.2.0.0/16" }
