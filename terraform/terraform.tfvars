region      = "us-east-2"
name        = "homelab-web"
environment = "lab"

vpc_cidr           = "10.20.0.0/16"
single_nat_gateway = true

instance_type  = "t3.micro"
instance_count = 2

allowed_http_cidrs = ["0.0.0.0/0"]

waf_rate_limit         = 2000
waf_log_retention_days = 14
