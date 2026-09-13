output "alb_dns_name" {
  description = "Public DNS name of the load balancer. Open http://<this> in a browser."
  value       = aws_lb.this.dns_name
}

output "alb_url" {
  description = "Convenience URL for the load balancer."
  value       = "http://${aws_lb.this.dns_name}"
}

output "instance_ids" {
  description = "IDs of the web instances."
  value       = aws_instance.web[*].id
}

output "instance_private_ips" {
  description = "Private IPs of the web instances."
  value       = aws_instance.web[*].private_ip
}

output "instance_azs" {
  description = "Availability Zone of each web instance."
  value       = aws_instance.web[*].availability_zone
}

output "web_acl_arn" {
  description = "ARN of the WAF web ACL associated with the ALB."
  value       = aws_wafv2_web_acl.this.arn
}

output "region" {
  description = "AWS region the stack is deployed in."
  value       = var.region
}

output "waf_log_group" {
  description = "CloudWatch Logs group holding the WAF logs."
  value       = aws_cloudwatch_log_group.waf.name
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}
