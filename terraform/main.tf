data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Latest Amazon Linux 2023 AMI, resolved at plan time so it never goes stale.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  # Two AZs is enough for an ALB and satisfies "each instance in a different subnet".
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # /16 split into:
  #   public   10.20.0.0/24, 10.20.1.0/24   -> ALB
  #   private  10.20.16.0/24, 10.20.17.0/24 -> web servers
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 16)]

  tags = merge(
    {
      Project     = var.name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}
