#Create Security Domains
resource "aviatrix_segmentation_security_domain" "ingress_sd" {
  domain_name = "ingress"
}

resource "aviatrix_segmentation_security_domain" "sharedsvc_sd" {
  domain_name = "sharedsvc"
}

resource "aviatrix_segmentation_security_domain" "spoke_sd" {
  for_each = var.spokes
  domain_name = each.key
}

#Create Segmentation Policies for shared services
resource "aviatrix_segmentation_security_domain_connection_policy" "spoke_to_sharedsvc" {
  for_each = var.spokes
  domain_name_1 = aviatrix_segmentation_security_domain.spoke_sd[each.key].domain_name
  domain_name_2 = aviatrix_segmentation_security_domain.sharedsvc_sd.domain_name
}

#Create Segmentation Policies for ingress
resource "aviatrix_segmentation_security_domain_connection_policy" "spoke_to_ingress" {
  for_each = var.spokes
  domain_name_1 = aviatrix_segmentation_security_domain.spoke_sd[each.key].domain_name
  domain_name_2 = aviatrix_segmentation_security_domain.ingress_sd.domain_name
}

#Create Transit and Egress Firenets
module "transit_firenet" {
  source  = "terraform-aviatrix-modules/aws-transit-firenet/aviatrix"
  version = "4.0.3"
  cidr    = var.transit_firenet_cidr
  region  = var.region
  account = var.account
  name    = "transit"
  enable_segmentation = true
  firewall_image = "Palo Alto Networks VM-Series Next-Generation Firewall Bundle 1"
}

module "egress_firenet" {
  source  = "terraform-aviatrix-modules/aws-transit-firenet/aviatrix"
  version = "4.0.3"
  cidr    = var.egress_firenet_cidr
  region  = var.region
  account = var.account
  name    = "egress"
  firewall_image = "Aviatrix FQDN Egress Filtering"
  enable_egress_transit_firenet = true
  fw_instance_size = "t3.medium"
}

#Create Ingress Spoke
module "ingress_spoke" {
  source  = "terraform-aviatrix-modules/aws-spoke/aviatrix"
  version = "4.0.3"
  name    = "ingress"
  cidr    = var.ingress_cidr
  region  = var.region
  account = var.account
  security_domain = aviatrix_segmentation_security_domain.ingress_sd.domain_name
  vpc_subnet_pairs = 2
  vpc_subnet_size  = 27
  transit_gw = module.transit_firenet.transit_gateway.gw_name
}

#Create Shared Services Spoke
module "sharedsvc_spoke" {
  source  = "terraform-aviatrix-modules/aws-spoke/aviatrix"
  version = "4.0.3"
  name    = "SharedSvc"
  cidr    = var.sharedsvc_cidr
  region  = var.region
  account = var.account
  security_domain = aviatrix_segmentation_security_domain.sharedsvc_sd.domain_name
  transit_gw = module.transit_firenet.transit_gateway.gw_name
}

#Create application spokes
module "app_spoke" {
  for_each = var.spokes
  source  = "terraform-aviatrix-modules/aws-spoke/aviatrix"
  version = "4.0.3"
  name    = each.key
  cidr    = each.value
  region  = var.region
  account = var.account
  security_domain = aviatrix_segmentation_security_domain.spoke_sd[each.key].domain_name
  vpc_subnet_pairs = 2
  vpc_subnet_size  = 19
  transit_gw = module.transit_firenet.transit_gateway.gw_name
  transit_gw_egress = module.egress_firenet.transit_gateway.gw_name
}

#Create Transit Firenet Inspection Policies
resource "aviatrix_transit_firenet_policy" "sharedsvc_inspect" {
  transit_firenet_gateway_name = module.transit_firenet.transit_gateway.gw_name
  inspected_resource_name      = "SPOKE:${module.sharedsvc_spoke.spoke_gateway.gw_name}"
  depends_on = [module.transit_firenet,module.sharedsvc_spoke]
}

resource "aviatrix_transit_firenet_policy" "ingress_inspect" {
  transit_firenet_gateway_name = module.transit_firenet.transit_gateway.gw_name
  inspected_resource_name      = "SPOKE:${module.ingress_spoke.spoke_gateway.gw_name}"
  depends_on = [module.transit_firenet,module.ingress_spoke]
}

resource "aviatrix_transit_firenet_policy" "app_inspect" {
  for_each = var.spokes
  transit_firenet_gateway_name = module.transit_firenet.transit_gateway.gw_name
  inspected_resource_name      = "SPOKE:${module.app_spoke[each.key].spoke_gateway.gw_name}"
  depends_on = [module.transit_firenet,module.app_spoke]
}

#Create FQDN Tag and associate egress gateways
resource "aviatrix_fqdn" "eks_fqdn" {
  fqdn_tag     = "centralized_egress"
  fqdn_enabled = true
  fqdn_mode    = "black"

  
  dynamic "gw_filter_tag_list" {
    for_each = { for fqdn in module.egress_firenet.aviatrix_firewall_instance: "${fqdn.gw_name}" => fqdn }
    content {
      gw_name = gw_filter_tag_list.value.gw_name
    }
  }
  
  depends_on = [ module.egress_firenet ]
  
  lifecycle {
    ignore_changes = all
  }
}

#Create Security Group for Ingress ALB
resource "aws_security_group" "ingress_alb_sg" {
  name        = "ingress_alb_sg"
  description = "SG for centralized EKS ingress ALB"
  vpc_id      = module.ingress_spoke.vpc.vpc_id
  
  tags = {
    Name = "ingress_alb_sg"
  }
}

#Create ALB SG rule for Prod
resource "aws_security_group_rule" "prod_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.ingress_alb_sg.id
}

#Create ALB SG rule for Dev
resource "aws_security_group_rule" "dev_http" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.ingress_alb_sg.id
}

#Create ALB SG rule for Egress
resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.ingress_alb_sg.id
}

#Create Ingress ALB for use with TargetGroup Bindings
resource "aws_lb" "eks_centralized_alb" {
  name               = "aviatrix-ingress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ingress_alb_sg.id]
  subnets            = [module.ingress_spoke.vpc.public_subnets[0].subnet_id,module.ingress_spoke.vpc.public_subnets[1].subnet_id]

  enable_deletion_protection = false

  tags = {
    Environment = "ingress"
  }
}

#Create Empty IP target group for Prod
resource "aws_lb_target_group" "eks_prod_tg" {
  name        = "avx-eks-demo-prod-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.ingress_spoke.vpc.vpc_id
}

#Create Empty IP target group for Dev
resource "aws_lb_target_group" "eks_dev_tg" {
  name        = "avx-eks-demo-dev-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.ingress_spoke.vpc.vpc_id
}

#Create Prod Listener on the Ingress ALB
resource "aws_lb_listener" "Prod-App" {
  load_balancer_arn = aws_lb.eks_centralized_alb.arn
  port              = "80"
  protocol          = "HTTP"
  #ssl_policy        = "ELBSecurityPolicy-2016-08"
  #certificate_arn   = "arn:aws:iam::187416307283:server-certificate/test_cert_rab3wuqwgja25ct3n4jdj2tzu4"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks_prod_tg.arn
  }
}

#Create Dev Listener on the Ingress ALB
resource "aws_lb_listener" "Dev-App" {
  load_balancer_arn = aws_lb.eks_centralized_alb.arn
  port              = "8080"
  protocol          = "HTTP"
  #ssl_policy        = "ELBSecurityPolicy-2016-08"
  #certificate_arn   = "arn:aws:iam::187416307283:server-certificate/test_cert_rab3wuqwgja25ct3n4jdj2tzu4"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks_dev_tg.arn
  }
}
