################################################################################
# WAFv2 web ACL, associated with the ALB
#
# REGIONAL scope is correct for an ALB (CLOUDFRONT scope is only for CloudFront).
################################################################################

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name}-waf"
  description = "WAF for the ${var.name} ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # AWS Managed: Core rule set (broad OWASP-style coverage).
  rule {
    name     = "AWSManagedCommonRules"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-common"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed: Known bad inputs.
  rule {
    name     = "AWSManagedKnownBadInputs"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Per-IP rate limit: blocks a source IP that exceeds the threshold in 5 minutes.
  rule {
    name     = "RateLimit"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-waf"
    sampled_requests_enabled   = true
  }

  tags = local.tags
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

################################################################################
# WAF logging to CloudWatch Logs
#
# The log group name MUST start with "aws-waf-logs-" or the logging
# configuration is rejected by the WAF API.
################################################################################

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.name}"
  retention_in_days = var.waf_log_retention_days

  tags = local.tags
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
}
