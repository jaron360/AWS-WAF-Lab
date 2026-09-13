################################################################################
# General
################################################################################

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "homelab-web"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, 3-30 characters."
  }
}

variable "environment" {
  description = "Environment tag value."
  type        = string
  default     = "lab"
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}

################################################################################
# Networking
################################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "single_nat_gateway" {
  description = <<-EOT
    Use one NAT Gateway for all private subnets (true) instead of one per AZ (false).
    true keeps cost down for a lab; false is more highly available. A NAT Gateway
    costs roughly $32/month plus data processing regardless of this setting.
  EOT
  type        = bool
  default     = true
}

################################################################################
# Web tier
################################################################################

variable "instance_type" {
  description = "EC2 instance type for the web servers."
  type        = string
  default     = "t3.micro"
}

variable "instance_count" {
  description = "Number of web server instances. Each lands in a different subnet/AZ."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 2 && var.instance_count <= 4
    error_message = "instance_count must be between 2 and 4 (bounded by the number of private subnets)."
  }
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB per instance."
  type        = number
  default     = 8
}

################################################################################
# Access
################################################################################

variable "allowed_http_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the load balancer on port 80. Defaults to the whole
    internet because this is a public web app fronted by WAF. Restrict to your own
    IP (["203.0.113.4/32"]) if you want it private.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.allowed_http_cidrs) > 0
    error_message = "Provide at least one CIDR in allowed_http_cidrs."
  }

  validation {
    condition     = alltrue([for c in var.allowed_http_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in allowed_http_cidrs must be a valid IPv4 CIDR block."
  }
}

################################################################################
# WAF
################################################################################

variable "waf_rate_limit" {
  description = "Requests per 5-minute window per source IP before WAF blocks it."
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 2000000000
    error_message = "waf_rate_limit must be between 100 and 2,000,000,000."
  }
}

variable "waf_log_retention_days" {
  description = "Retention in days for WAF logs in CloudWatch Logs."
  type        = number
  default     = 14
}
