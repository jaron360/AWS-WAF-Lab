module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.name
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  # Private instances reach the internet (package installs, updates) through NAT.
  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  # Do not auto-assign public IPs; the ALB is the only public entry point.
  map_public_ip_on_launch = false

  tags = local.tags
}
