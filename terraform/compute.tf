################################################################################
# Security groups
################################################################################

# ALB: accepts HTTP from the allowed CIDRs, talks to instances on 80.
resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "Ingress to the ALB on port 80"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.tags, { Name = "${var.name}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "alb_ingress_http" {
  security_group_id = aws_security_group.alb.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = var.allowed_http_cidrs
  description       = "HTTP from allowed clients"
}

resource "aws_security_group_rule" "alb_egress_to_web" {
  security_group_id        = aws_security_group.alb.id
  type                     = "egress"
  protocol                 = "tcp"
  from_port                = 80
  to_port                  = 80
  source_security_group_id = aws_security_group.web.id
  description              = "Forward to web instances"
}

# Web instances: accept HTTP only from the ALB, all egress allowed (for updates).
resource "aws_security_group" "web" {
  name_prefix = "${var.name}-web-"
  description = "HTTP from the ALB only"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.tags, { Name = "${var.name}-web" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "web_ingress_from_alb" {
  security_group_id        = aws_security_group.web.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 80
  to_port                  = 80
  source_security_group_id = aws_security_group.alb.id
  description              = "HTTP from the ALB"
}

resource "aws_security_group_rule" "web_egress_all" {
  security_group_id = aws_security_group.web.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound (package installs, updates)"
}

################################################################################
# Web instances
#
# One instance per private subnet, so each lands in a different subnet/AZ.
# user_data installs a tiny static site that prints the hostname and AZ, which
# makes ALB balancing visible: refresh and the served AZ alternates.
################################################################################

resource "aws_instance" "web" {
  count = var.instance_count

  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = module.vpc.private_subnets[count.index % length(module.vpc.private_subnets)]
  vpc_security_group_ids = [aws_security_group.web.id]

  # Enforce IMDSv2 to blunt SSRF-to-credentials attacks.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    dnf install -y httpd
    systemctl enable --now httpd

    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
    AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/placement/availability-zone)
    IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/instance-id)

    cat > /var/www/html/index.html <<HTML
    <!doctype html>
    <html><head><title>${var.name}</title></head>
    <body style="font-family:sans-serif;max-width:640px;margin:4rem auto">
      <h1>${var.name}</h1>
      <p>Served by <strong>$IID</strong></p>
      <p>Availability Zone: <strong>$AZ</strong></p>
      <p>Refresh to watch the load balancer alternate between instances.</p>
    </body></html>
    HTML

    # Lightweight health endpoint for the ALB target group.
    echo "ok" > /var/www/html/health
  EOF

  # Re-provision if user_data changes.
  user_data_replace_on_change = true

  tags = merge(local.tags, { Name = "${var.name}-${count.index + 1}" })
}
