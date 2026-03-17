terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28.0"
    }
    http = {
      source = "hashicorp/http"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"

  default_tags {
    tags = {
      Environment = "dev"
      Owner       = "terraform"
    }
  }
}

provider "aws" {
  alias  = "tokyo"
  region = "ap-northeast-1"
}

provider "aws" {
  alias  = "saopaulo"
  region = "sa-east-1"
}


resource "aws_vpc" "ShibuyaCrossing_vpc" {
  cidr_block           = "10.237.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    local.tags,
  { name = "ShibuyaCrossing_vpc" })
}

# Internet gateway
resource "aws_internet_gateway" "ShibuyaCrossing_igw" {
  vpc_id = aws_vpc.ShibuyaCrossing_vpc.id
  tags = merge(
    local.tags,
    { name = "${local.project_name}-igw" }
  )
}

# Nat gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = merge(
    local.tags,
  { name = "${local.project_name}-nat-eip" })
}

# Explanation: NAT is ShibuyaCrossing’s smuggler tunnel—private subnets can reach out without being seen.
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_ShibuyaCrossing[0].id # NAT in a public subnet
  tags = merge(
    local.tags,
  { name = "${local.project_name}-nat" })

  depends_on = [aws_internet_gateway.ShibuyaCrossing_igw, aws_route_table.ShibuyaCrossing_public_rt]
}

############################################
# Move EC2 into PRIVATE subnet (no public IP)
############################################

# Explanation: This is your “Han Solo box”—it talks to RDS and complains loudly when the DB is down.
resource "aws_instance" "ShibuyaCrossing_ec2" {
  ami                         = data.aws_ssm_parameter.amzn2_ami.value
  instance_type               = local.instance_type
  key_name                    = null
  subnet_id                   = aws_subnet.private_ShibuyaCrossing[0].id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false
  user_data_replace_on_change = true

  user_data = <<-EOF
  #!/bin/bash
  yum update -y
  yum install -y python3
  echo "userdata ran" > /tmp/userdata_ok.txt
EOF

  tags = merge(
    local.tags,
  { name = "${local.project_name}-ec2-app" })
}
# Explanation: EC2 SG is lab1c’s bodyguard—only let in what you mean to.
resource "aws_security_group" "ec2_sg" {
  name        = "${local.project_name}-ec2-sg"
  description = "EC2 app security group"
  vpc_id      = aws_vpc.ShibuyaCrossing_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.ShibuyaCrossing_alb_sg.id]
  }

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
  { name = "${local.project_name}-ec2-sg" })
}


# TODO: student adds inbound rules (HTTP 80, SSH 22 from their IP)
# TODO: student ensures outbound allows DB port to RDS SG (or allow all outbound)

# Explanation: RDS SG is the Rebel vault—only the app server gets a keycard.

resource "aws_security_group" "rds_sg" {
  name        = "${local.project_name}-rds-sg"
  description = "RDS security group"
  vpc_id      = aws_vpc.ShibuyaCrossing_vpc.id

  ingress {
    description     = "MySQL from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
  { name = "${local.project_name}-rds-sg" })
}

resource "aws_security_group" "vpce_allow_tls" {
  name        = "${local.project_name}-vpce-allow-tls"
  description = "Allow TLS from inside VPC to interface endpoints"
  vpc_id      = aws_vpc.ShibuyaCrossing_vpc.id

  tags = merge(local.tags, {
    Name = "${local.project_name}-vpce-allow-tls"
  })
}

# Ingress: 443 from VPC IPv4 CIDR
resource "aws_vpc_security_group_ingress_rule" "vpce_tls_ipv4" {
  security_group_id = aws_security_group.vpce_allow_tls.id
  cidr_ipv4         = aws_vpc.ShibuyaCrossing_vpc.cidr_block
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "TLS from VPC IPv4"
}

# Egress: allow all outbound IPv4
resource "aws_vpc_security_group_egress_rule" "vpce_all_ipv4" {
  security_group_id = aws_security_group.vpce_allow_tls.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound IPv4"
}
############################################
# Target Group + Attachment
############################################

# Explanation: Target groups are tokyo’s “who do I forward to?” list — private EC2 lives here.
resource "aws_lb_target_group" "ShibuyaCrossing_tg01" {
  name        = "${var.project_name}-tg01"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ShibuyaCrossing_vpc.id
  target_type = "instance"

  # TODO: students set health check path to something real (e.g., /health)
  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    matcher             = "200-399"
  }

  tags = merge(local.tags, { name = "ShibuyaCrossing_tg01" })
}

# Explanation: tokyo personally introduces the ALB to the private EC2 — “this is my friend, don’t shoot.”
resource "aws_lb_target_group_attachment" "ShibuyaCrossing_tg_attach01" {
  target_group_arn = aws_lb_target_group.ShibuyaCrossing_tg01.arn
  target_id        = aws_instance.ShibuyaCrossing_ec2.id
  port             = 80
}
# TODO: students ensure EC2 security group allows inbound from ALB SG on this port (rule above)

############################################
# VPC Endpoint -  Rds endpoint (Interface)
############################################

# Explanation: S3 is the supply depot—without this, your private world starves (updates, artifacts, logs).
resource "aws_vpc_endpoint" "lab_rds" {
  provider            = aws.tokyo
  vpc_id              = aws_vpc.ShibuyaCrossing_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce_allow_tls.id]

  tags = merge(local.tags, {
    Name = "${local.project_name}-vpce-ssm-extra"
  })
}

############################################
# VPC Endpoint - S3 (Gateway)
############################################

# Explanation: S3 is the supply depot—without this, your private world starves (updates, artifacts, logs).
resource "aws_vpc_endpoint" "s3" {
  provider          = aws.tokyo
  vpc_id            = aws_vpc.ShibuyaCrossing_vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.ShibuyaCrossing_public_rt.id,
    aws_route_table.ShibuyaCrossing_private_rt.id
  ]

  tags = merge(local.tags, {
    Name = "${var.project_name}-s3-endpoint"
  })
}

############################################
# VPC Endpoints - SSM (Interface)
############################################

# Explanation: SSM is your Force choke—remote control without SSH, and nobody sees your keys.
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.ShibuyaCrossing_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = false

  subnet_ids         = local.private_subnet_ids
  security_group_ids = [aws_security_group.vpce_allow_tls.id]
}

# Explanation: ec2messages is the Wookiee messenger—SSM sessions won’t work without it.
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.ShibuyaCrossing_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = local.private_subnet_ids
  security_group_ids = [aws_security_group.vpce_allow_tls.id]

  tags = merge(
    local.tags,
  { name = "${local.project_name}-vpce-ec2messages" })
}

# Explanation: ssmmessages is the holonet channel—Session Manager needs it to talk back.
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.ShibuyaCrossing_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = local.private_subnet_ids
  security_group_ids = [aws_security_group.vpce_allow_tls.id]

  tags = merge(
    local.tags,
  { name = "${local.project_name}-vpce-ssmmessages" })
}

############################################
# VPC Endpoint - CloudWatch Logs (Interface)
############################################

# Explanation: CloudWatch Logs is the ship’s black box—Chewbacca wants crash data, always.
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.ShibuyaCrossing_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce_allow_tls.id]

  tags = merge(
    local.tags,
  { name = "${local.project_name}-vpce-logs" })
}

############################################
# VPC Endpoint - Secrets Manager (Interface)
############################################

# Explanation: Secrets Manager is the locked vault—Chewbacca doesn’t put passwords on sticky notes.
resource "aws_vpc_endpoint" "secrets" {
  vpc_id              = aws_vpc.ShibuyaCrossing_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce_allow_tls.id]

  tags = merge(
    local.tags,
  { name = "${local.project_name}-vpce-secrets" })
}

############################################
# VPC Endpoint - KMS (Interface)
############################################

# Explanation: KMS is the encryption kyber crystal—Chewbacca prefers locked doors AND locked safes.
resource "aws_vpc_endpoint" "kms" {
  vpc_id              = aws_vpc.ShibuyaCrossing_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.kms"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce_allow_tls.id]

  tags = merge(
    local.tags,
  { name = "${local.project_name}-vpce-kms" })
}

############################################
# Bonus B - Route53 (Hosted Zone + DNS records + ACM validation + ALIAS to ALB)
############################################

############################################
# Hosted Zone (optional creation)
############################################

# Explanatio# Create hosted zone only if you want Terraform to manage it
resource "aws_route53_zone" "passportpookie" {
  count = var.manage_route53_in_terraform ? 1 : 0
  name  = local.zone_name

  tags = merge(local.tags, {
    Name = "${var.project_name}-zone"
  })
}

# Otherwise, read the existing hosted zone by ID
data "aws_route53_zone" "passportpookie_existing" {
  count   = var.manage_route53_in_terraform ? 0 : 1
  zone_id = "Z09361711HDESSBG6MZ22"
}


############################################
# ACM DNS Validation Records
############################################

# Explanation: ACM asks “prove you own this planet”—DNS validation is ShibuyaCrossing roaring in the right place.
resource "aws_route53_record" "ShibuyaCrossing_acm_validation_records01" {
  for_each = {
    for dvo in aws_acm_certificate.ShibuyaCrossing_acm_cert.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = local.passportpookie_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60

  records = [each.value.record]
}

# Explanation: This ties the “proof record” back to ACM—ShibuyaCrossing gets his green checkmark for TLS.
resource "aws_acm_certificate_validation" "ShibuyaCrossing_acm_validation" {
  certificate_arn         = aws_acm_certificate.ShibuyaCrossing_acm_cert.arn
  validation_record_fqdns = [for r in aws_route53_record.ShibuyaCrossing_acm_validation_records01 : r.fqdn]
}

############################################
# ALIAS record: app.ShibuyaCrossing-growl.com -> ALB
############################################
/*
# Explanation: This is the holographic sign outside the cantina—app.ShibuyaCrossing-growl.com points to your ALB.
resource "aws_route53_record" "ShibuyaCrossing_app_alias" {
  zone_id = "Z09361711HDESSBG6MZ22"
  name    = local.app_subdomain
  type    = "A"

  alias {
    name                   = aws_lb.ShibuyaCrossing_alb.dns_name
    zone_id                = aws_lb.ShibuyaCrossing_alb.zone_id
    evaluate_target_health = true
  }
}
*/


############################################
# WAFv2 Web ACL (Basic managed rules)
############################################

# Explanation: WAF is the shield generator — it blocks the cheap blaster fire before it hits your ALB.
resource "aws_wafv2_web_acl" "ShibuyaCrossing_waf01" {
  count = var.enable_waf ? 1 : 0

  name  = "ShibuyaCrossing_waf01"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ShibuyaCrossing_waf01"
    sampled_requests_enabled   = true
  }

  # Explanation: AWS managed rules are like hiring Rebel commandos — they’ve seen every trick.
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-waf-common"
      sampled_requests_enabled   = true
    }
  }

  # Log4j protection rule
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-waf-log4j"
      sampled_requests_enabled   = true
    }
  }

  tags = {
    Name = "ShibuyaCrossing_waf01"
  }
}

# CloudWatch Log Group for WAF
resource "aws_cloudwatch_log_group" "waf_log_group" {
  count = var.enable_waf ? 1 : 0

  name              = "aws-waf-logs-ShibuyaCrossing_waf01"
  retention_in_days = 7

  tags = {
    Name = "ShibuyaCrossing_waf-logs"
  }
}

# WAF Logging Configuration
resource "aws_wafv2_web_acl_logging_configuration" "lab2_waf_logging" {
  count                   = var.enable_waf ? 1 : 0
  resource_arn            = aws_wafv2_web_acl.ShibuyaCrossing_waf01[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_log_group[0].arn]
}

# Explanation: Attach the shield generator to the customs checkpoint — ALB is now protected.
resource "aws_wafv2_web_acl_association" "lab2_waf_assoc01" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_lb.ShibuyaCrossing_alb.arn
  web_acl_arn  = aws_wafv2_web_acl.ShibuyaCrossing_waf01[0].arn
}

# Explanation: Secrets Manager is lab1c’s locked holster—credentials go here, not in code.
resource "aws_secretsmanager_secret" "db_creds" {
  name = var.secrets_manager
  tags = local.tags
}

resource "random_password" "db_password" {
  length  = 16
  special = false
}

# Explanation: Secret payload—students should align this structure with their app (and support rotation later).
resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id = aws_secretsmanager_secret.db_creds.id
  secret_string = jsonencode({
    username = local.db_username
    password = random_password.db_password.result
    host     = aws_db_instance.lab_rds.address
    port     = 3306
    dbname   = local.db_name
  })
}

# Explanation: This is the holocron of state—your relational data lives here, not on the EC2.
resource "aws_db_instance" "lab_rds" {
  identifier             = "${local.project_name}-mysql"
  engine                 = "mysql"
  engine_version         = "8.4.7"
  instance_class         = local.db_instance_class
  allocated_storage      = 20
  username               = local.db_username
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.lab_rds.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  multi_az               = false
  db_name                = local.db_name


  # TODO: student sets multi_az / backups / monitoring as stretch goals

  tags = merge(
    local.tags,
    { Name = "${local.project_name}-mysql" }
  )
}

# Public Subnets (3 AZs)
resource "aws_subnet" "public_ShibuyaCrossing" {
  count                   = 3
  vpc_id                  = aws_vpc.ShibuyaCrossing_vpc.id
  cidr_block              = cidrsubnet("10.237.0.0/16", 8, count.index + 100)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    local.tags, {
  Name = "${var.project_name}-public_ShibuyaCrossing-${count.index + 1}" })
}

# Private Subnets (3 AZs)
resource "aws_subnet" "private_ShibuyaCrossing" {
  count                   = 3
  vpc_id                  = aws_vpc.ShibuyaCrossing_vpc.id
  cidr_block              = cidrsubnet("10.237.0.0/16", 8, count.index + 110)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    local.tags, {
  Name = "${var.project_name}-private_ShibuyaCrossing-${count.index + 1}" })
}

# Explanation: RDS hides in private subnets like the Rebel base on Hoth—cold, quiet, and not public.
resource "aws_db_subnet_group" "lab_rds" {
  name       = "${local.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private_ShibuyaCrossing[*].id

  tags = merge(
    local.tags,
    { Name = "${local.project_name}-db-subnet-group" }
  )
}

# Explanation: Parameter Store is lab1c’s map—endpoints and config live here for fast recovery.
resource "aws_ssm_document" "tokyo_alarm_report_runbook" {
  name            = "${var.project_name}-tokyo-incident-report"
  document_type   = "Automation"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Incident response runbook for ${var.project_name}"
    mainSteps = [
      {
        name   = "generateReport"
        action = "aws:executeScript"
        inputs = {
          Runtime = "python3.11"
          Handler = "script_handler"
          Script  = <<-PY
            def script_handler(events, context):
                return {"status": "ok"}
          PY
        }
      }
    ]
  })
}

resource "aws_ssm_parameter" "db_endpoint" {
  name  = "/lab/db/endpoint"
  type  = "String"
  value = aws_db_instance.lab_rds.address

  tags = merge(
    local.tags,
    { Name = "${local.project_name}-param-db-endpoint" }
  )
}

resource "aws_ssm_parameter" "db_port" {
  name  = "/lab/db/port"
  type  = "String"
  value = tostring(aws_db_instance.lab_rds.port)

  tags = merge(
    local.tags,
    { Name = "${local.project_name}-param_db_port" }
  )
}

# Explanation: DB name is the label on the crate—without it, you’re rummaging in the dark.
resource "aws_ssm_parameter" "db_name" {
  name  = "/lab/db/name"
  type  = "String"
  value = local.db_name

  tags = merge(
    local.tags,
  { Name = "${local.project_name}-param-db-name" })
}

data "aws_ssm_parameter" "amzn2_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

############################################
# CloudWatch Alarm: ALB 5xx -> SNS
############################################

# Explanation: When the ALB starts throwing 5xx, that’s the Falcon coughing — page the on-call Wookiee.
resource "aws_cloudwatch_metric_alarm" "ShibuyaCrossing_alb_5xx_alarm" {
  alarm_name          = "${var.project_name}-alb-5xx-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alb_5xx_evaluation_periods
  threshold           = var.alb_5xx_threshold
  period              = var.alb_5xx_period_seconds
  statistic           = "Sum"

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"

  dimensions = {
    LoadBalancer = aws_lb.ShibuyaCrossing_alb.arn_suffix
  }

  alarm_actions = [aws_sns_topic.db_incidents.arn]

  tags = {
    Name = "ShibuyaCrossing-alb-5xx-alarm"
  }
}

############################################
# CloudWatch Dashboard (Skeleton)
############################################

# Explanation: Dashboards are your cockpit HUD — ShibuyaCrossing wants dials, not vibes.
resource "aws_cloudwatch_dashboard" "ShibuyaCrossing_dashboard01" {
  dashboard_name = "${var.project_name}-dashboard01"

  # TODO: students can expand widgets; this is a minimal workable skeleton
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.ShibuyaCrossing_alb.arn_suffix],
            [".", "HTTPCode_ELB_5XX_Count", ".", aws_lb.ShibuyaCrossing_alb.arn_suffix]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "ShibuyaCrossing ALB: Requests + 5XX"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.ShibuyaCrossing_alb.arn_suffix]
          ]
          period = 300
          stat   = "Average"
          region = local.region
          title  = "ShibuyaCrossing ALB: Target Response Time"
        }
      }
    ]
  })
}

# Explanation: When the Falcon is on fire, logs tell you *which* wire sparked—ship them centrally.
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/aws/ec2/${local.project_name}-rds-app"
  retention_in_days = 7
  tags              = local.tags
}

resource "aws_cloudwatch_log_metric_filter" "db_connection_errors" {
  name           = "${local.project_name}-db-connection-errors"
  log_group_name = aws_cloudwatch_log_group.app_logs.name

  pattern = <<EOF
 ?"pymysql.err.OperationalError" ?"Can't connect" ?"Error" ?"failed" ?"Access denied"
 EOF

  metric_transformation {
    name      = "DBConnectionErrors"
    namespace = "Lab/RDSApp"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "db-connection_failure" {
  alarm_name          = "ShibuyaCrossing-db-connection-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DBConnectionErrors"
  namespace           = "Lab/RDSApp"
  period              = 300
  statistic           = "Sum"
  threshold           = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.db_incidents.arn]

  tags = merge(local.tags, {
    Name = "ShibuyaCrossing_db_connection_errors_alarm"
  })

  depends_on = [
    aws_cloudwatch_log_metric_filter.db_connection_errors
  ]
}

############################################
# Bonus G - Bedrock Auto Incident Report Pipeline (SNS -> Lambda -> S3)
############################################

#checkov:skip=CKV_AWS_144: Cross-region replication not required for lab IR reports bucket
resource "aws_s3_bucket" "ShibuyaCrossing_ir_reports_bucket" {
  bucket = "${var.project_name}-ir-reports-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "ShibuyaCrossing_ir_reports_versioning" {
  bucket = aws_s3_bucket.ShibuyaCrossing_ir_reports_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ShibuyaCrossing_ir_reports_encryption" {
  bucket = aws_s3_bucket.ShibuyaCrossing_ir_reports_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_logging" "ShibuyaCrossing_ir_reports_logging" {
  bucket        = aws_s3_bucket.ShibuyaCrossing_ir_reports_bucket.id
  target_bucket = aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket.id
  target_prefix = "ir-reports-access-logs/"
}

/*resource "aws_s3_bucket_notification" "ShibuyaCrossing_ir_reports_notification" {
  bucket = aws_s3_bucket.ShibuyaCrossing_ir_reports_bucket.id
  topic {
    topic_arn = aws_sns_topic.db_incidents.arn
    events    = ["s3:ObjectCreated:*"]
  }
}
*/
resource "aws_s3_bucket_lifecycle_configuration" "ShibuyaCrossing_ir_reports_lifecycle" {
  bucket = aws_s3_bucket.ShibuyaCrossing_ir_reports_bucket.id
  rule {
    id     = "expire-old-reports"
    status = "Enabled"

    expiration {
      days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "ShibuyaCrossing_ir_reports_pab" {
  bucket                  = aws_s3_bucket.ShibuyaCrossing_ir_reports_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "ShibuyaCrossing_ir_lambda_role" {
  name = "${var.project_name}-ir-lambda-role01"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "ShibuyaCrossing_ir_lambda_policy01" {
  name = "${var.project_name}-ir-lambda-policy01"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:StartQuery",
          "logs:GetQueryResults",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:FilterLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "cloudwatch:DescribeAlarms",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ],
        Resource = "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/lab/db/*"
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/rds/mysql*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.ShibuyaCrossing_ir_reports_bucket.arn,
          "${aws_s3_bucket.ShibuyaCrossing_ir_reports_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "bedrock:InvokeModel"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ShibuyaCrossing_ir_lambda_attach" {
  role       = aws_iam_role.ShibuyaCrossing_ir_lambda_role.name
  policy_arn = aws_iam_policy.ShibuyaCrossing_ir_lambda_policy01.arn
}

resource "aws_iam_role_policy_attachment" "ShibuyaCrossing_ir_lambda_basiclogs" {
  role       = aws_iam_role.ShibuyaCrossing_ir_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_signer_signing_profile" "ShibuyaCrossing_ir_lambda_signing_profile" {
  platform_id = "AWSLambda-SHA384-ECDSA"
  name        = "${var.project_name}_ir_lambda_"
}

resource "aws_lambda_code_signing_config" "ShibuyaCrossing_ir_lambda_csc" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.ShibuyaCrossing_ir_lambda_signing_profile.version_arn]
  }
  policies {
    untrusted_artifact_on_deployment = "Enforce"
  }
}

resource "aws_lambda_function" "ShibuyaCrossing_ir_lambda" {
  function_name = "${var.project_name}-ir-reporter01"
  role          = aws_iam_role.ShibuyaCrossing_ir_lambda_role.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60

  filename         = "${path.module}/lambda_ir_reporter.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_ir_reporter.zip")


  depends_on = [
    aws_iam_role_policy_attachment.ShibuyaCrossing_ir_lambda_attach,
    aws_iam_role_policy_attachment.ShibuyaCrossing_ir_lambda_basiclogs
  ]
}

############################################
# Bonus B - WAF Logging (CloudWatch Logs OR S3 OR Firehose)
# One destination per Web ACL, choose via var.waf_log_destination.
############################################

############################################
# CloudWatch Logs destination
############################################
resource "aws_cloudwatch_log_group" "ShibuyaCrossing_waf_log_group01" {
  count = var.enable_waf && var.waf_log_destination == "cloudwatch" ? 1 : 0

  name              = "aws-waf-logs-${var.project_name}-webacl01"
  retention_in_days = var.waf_log_retention_days

  tags = {
    Name = "${var.project_name}-waf-log-group01"
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "ShibuyaCrossing_waf_logging01" {
  count = var.enable_waf && var.waf_log_destination == "cloudwatch" ? 1 : 0

  resource_arn = aws_wafv2_web_acl.ShibuyaCrossing_waf01[0].arn

  log_destination_configs = [
    aws_cloudwatch_log_group.ShibuyaCrossing_waf_log_group01[0].arn
  ]

  depends_on = [aws_wafv2_web_acl.ShibuyaCrossing_waf01]
}

############################################
# S3 destination
############################################
resource "aws_s3_bucket" "ShibuyaCrossing_waf_logs_bucket01" {
  count  = var.enable_waf && var.waf_log_destination == "s3" ? 1 : 0
  bucket = "aws-waf-logs-${var.project_name}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-waf-logs-bucket01"
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_public_access_block" "ShibuyaCrossing_waf_logs_pab01" {
  count = var.enable_waf && var.waf_log_destination == "s3" ? 1 : 0

  bucket                  = aws_s3_bucket.ShibuyaCrossing_waf_logs_bucket01[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_wafv2_web_acl_logging_configuration" "ShibuyaCrossing_waf_logging_s3_01" {
  count = var.enable_waf && var.waf_log_destination == "s3" ? 1 : 0

  resource_arn = aws_wafv2_web_acl.ShibuyaCrossing_waf01[0].arn

  log_destination_configs = [
    aws_s3_bucket.ShibuyaCrossing_waf_logs_bucket01[0].arn
  ]

  depends_on = [aws_wafv2_web_acl.ShibuyaCrossing_waf01]
}

############################################
# Least-Privilege IAM (BONUS A)
############################################

# Explanation: Chewbacca doesn’t hand out the Falcon keys—this policy scopes reads to your lab paths only.
resource "aws_iam_policy" "ShibuyaCrossing_leastpriv_read_params" {
  name        = "${local.project_name}-lp-ssm-read01"
  description = "Least-privilege read for SSM Parameter Store under /lab/db/*"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLabDbParams"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter/lab/db/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "cloudfront_role" {
  name = "cloudfront_role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    "tag-key" = "tag-value"
    scope     = "global"
  }
}


# Explanation: Chewbacca only opens *this* vault—GetSecretValue for only your secret (not the whole planet).
resource "aws_iam_policy" "ShibuyaCrossing_lp_read_secret01" {
  name        = "${local.project_name}-lp-secrets-read01"
  description = "Least-privilege read for the lab DB secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOnlyLabSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = local.secret_arn_guess
      }
    ]
  })
}

resource "aws_iam_role" "Lambda_role" {
  name = "Lambda_role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    "tag-key" = "tag-value"
    scope     = "global"
  }
}
# Explanation: When the Falcon logs scream, this lets Chewbacca ship logs to CloudWatch without giving away the Death Star plans.
resource "aws_iam_policy" "ShibuyaCrossing_lp_cwlogs01" {
  name        = "${local.project_name}-lp-cwlogs01"
  description = "Least-privilege CloudWatch Logs write for the app log group"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.app_logs.arn}:*"
        ]
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "attach_lp_params01" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ShibuyaCrossing_leastpriv_read_params.arn
}

resource "aws_iam_role_policy_attachment" "attach_lp_secret01" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ShibuyaCrossing_lp_read_secret01.arn
}

resource "aws_iam_role_policy_attachment" "attach_lp_cwlogs01" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ShibuyaCrossing_lp_cwlogs01.arn
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_policy" "secretsmanager_read_policy" {
  name        = "test_policy"
  path        = "/"
  description = "My test policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "ReadSpecificSecret",
        "Effect" : "Allow",
        "Action" : ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        "Resource" : "arn:aws:secretsmanager:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:secret:${var.secrets_manager}*" #Remember add a or your policy will not work
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "example_attachment4" {
  role = aws_iam_role.ec2_role.id
  # Secrets Manager Read Access to allow access to RDS credentials
  policy_arn = aws_iam_policy.secretsmanager_read_policy.arn
}

resource "aws_iam_role_policy" "ssm_policy" {
  name = "${local.project_name}-ssm-access"
  role = aws_iam_role.ec2_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/lab/db/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudwatch_policy" {
  name = "${local.project_name}-cloudwatch-access"
  role = aws_iam_role.ec2_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = "arn:aws:logs:${local.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/${local.project_name}-rds-app*:*"
      }
    ]
  })
}

# Explanation: Instance profile is the harness that straps the role onto the EC2 like bandolier ammo.
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Explanation: lab1c refuses to carry static keys—this role lets EC2 assume permissions safely.
resource "aws_iam_role" "ec2_role" {
  name = "${local.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

############################################
# Bonus B - Route53 Zone Apex + ALB Access Logs to S3
############################################

############################################
# Route53: Zone Apex (root domain) -> ALB
############################################
/*
# Explanation: The zone apex is the throne room—ShibuyaCrossing-growl.com itself should lead to the ALB.
resource "aws_route53_record" "ShibuyaCrossing_apex_alias01" {
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.ShibuyaCrossing_alb.dns_name
    zone_id                = aws_lb.ShibuyaCrossing_alb.zone_id
    evaluate_target_health = true
  }
}
*/

############################################
# S3 bucket for ALB access logs
############################################

resource "aws_s3_bucket" "ShibuyaCrossing_alb_logs_bucket" {
  bucket        = "shibuyacrossing-alb-logs-961341540291"
  force_destroy = true
}

# Disable versioning to allow clean deletion
resource "aws_s3_bucket_versioning" "ShibuyaCrossing_alb_logs_versioning" {
  bucket = aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket.id

  versioning_configuration {
    status = "Disabled"
  }
}

# Explanation: Encrypt logs at rest—ShibuyaCrossing protects the black box with cryptography.
resource "aws_s3_bucket_server_side_encryption_configuration" "ShibuyaCrossing_alb_logs_encryption" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Explanation: Block public access—ShibuyaCrossing does not publish the ship’s black box to the galaxy.
resource "aws_s3_bucket_public_access_block" "ShibuyaCrossing_alb_logs_pab01" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket                  = aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Explanation: Bucket ownership controls prevent log delivery chaos—ShibuyaCrossing likes clean chain-of-custody.
resource "aws_s3_bucket_ownership_controls" "ShibuyaCrossing_alb_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Explanation: TLS-only—ShibuyaCrossing growls at plaintext and throws it out an airlock.

resource "aws_s3_bucket_policy" "ShibuyaCrossing_alb_logs_policy" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowALBLogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket.bucket}/${var.alb_access_logs_prefix != "" ? "${var.alb_access_logs_prefix}/" : ""}AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket.bucket}",
          "arn:aws:s3:::${aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket.bucket}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

############################################
# Enable ALB access logs (on the ALB resource)
############################################

# Explanation: Turn on access logs—ShibuyaCrossing wants receipts when something goes wrong.
# NOTE: This is a skeleton patch: students must merge this into aws_lb.ShibuyaCrossing_alb
# by adding/accessing the `access_logs` block. Terraform does not support "partial" blocks.
#
# Add this inside resource "aws_lb" "ShibuyaCrossing_alb" { ... } in bonus_b.tf:

# access_logs {
#   bucket  = aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket.bucket
#   prefix  = var.alb_access_logs_prefix
#   enabled = var.enable_alb_access_logs
# }

resource "aws_s3_bucket_ownership_controls" "ShibuyaCrossing_alb_logs_owner" {
  bucket = aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# transit gateway route table in ShibuyaCrossing is the station map—without it, you’re lost in the city.
resource "aws_ec2_transit_gateway_route_table" "ShibuyaCrossing_tgw_rt" {
  provider           = aws.tokyo
  transit_gateway_id = aws_ec2_transit_gateway.ShibuyaCrossing_tgw.id

  tags = merge(local.tags, {
    Name = "ShibuyaCrossing-tgw-rt"
  })
}

# Explanation: ShibuyaCrossing connects to the ShibuyaCrossing VPC—this is the gate to the medical records vault.
resource "aws_ec2_transit_gateway_vpc_attachment" "ShibuyaCrossing_attach_ShibuyaCrossing_vpc01" {
  transit_gateway_id = aws_ec2_transit_gateway.ShibuyaCrossing_tgw.id
  vpc_id             = aws_vpc.ShibuyaCrossing_vpc.id
  provider           = aws.tokyo
  subnet_ids         = aws_subnet.private_ShibuyaCrossing[*].id
  tags               = { Name = "ShibuyaCrossing-attach-ShibuyaCrossing-vpc01" }
}

resource "aws_ec2_transit_gateway_peering_attachment" "ShibuyaCrossing_to_liberdade" {
  provider = aws.tokyo

  peer_account_id         = data.aws_caller_identity.current.account_id
  peer_region             = "sa-east-1"
  peer_transit_gateway_id = aws_ec2_transit_gateway.liberdade_tgw.id
  transit_gateway_id      = aws_ec2_transit_gateway.ShibuyaCrossing_tgw.id

  tags = merge(
    local.tags,
    {
      Name = "ShibuyaCrossing-to-liberdade-peering"
    }
  )
}

############################################
# Security Group: ALB
############################################
resource "aws_security_group" "ShibuyaCrossing_alb_sg" {
  name        = "ShibuyaCrossing-alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.ShibuyaCrossing_vpc.id

  tags = {
    Name = "ShibuyaCrossing-alb-sg"
  }
}

# Inbound 80 from anywhere
resource "aws_security_group_rule" "alb_ingress" {
  type              = "ingress"
  security_group_id = aws_security_group.ShibuyaCrossing_alb_sg.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Inbound 443 from anywhere
resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  security_group_id = aws_security_group.ShibuyaCrossing_alb_sg.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Outbound only to EC2 app port (80) on the EC2 SG
resource "aws_security_group_rule" "alb_egress_to_ec2_http" {
  type                     = "egress"
  security_group_id        = aws_security_group.ShibuyaCrossing_alb_sg.id
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ec2_sg.id
}

/*# Allow ALB -> EC2 on app port (80)
resource "aws_security_group_rule" "ShibuyaCrossing_ec2_ingress_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ec2_sg.id
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ShibuyaCrossing_alb_sg.id
}
*/

############################################
# Application Load Balancer
############################################
resource "aws_lb" "ShibuyaCrossing_alb" {
  name               = "ShibuyaCrossing-alb"
  load_balancer_type = "application"
  internal           = false

  security_groups = [aws_security_group.ShibuyaCrossing_alb_sg.id]
  subnets         = local.public_subnet_ids

  enable_deletion_protection = false

  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs ? [1] : []
    content {
      bucket  = aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket.bucket
      prefix  = var.alb_access_logs_prefix
      enabled = var.enable_alb_access_logs
    }
  }

  depends_on = [
    aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket,
    aws_s3_bucket_public_access_block.ShibuyaCrossing_alb_logs_pab01,
    aws_s3_bucket_ownership_controls.ShibuyaCrossing_alb_logs_owner,
    aws_s3_bucket_policy.ShibuyaCrossing_alb_logs_policy
  ]

  tags = {
    Name = "${var.project_name}-alb"
  }
}

############################################
# ACM Certificate (TLS) for app.passportpookie.click (no http://)
############################################
resource "aws_acm_certificate" "ShibuyaCrossing_acm_cert" {
  domain_name               = local.fqdn
  subject_alternative_names = [local.app_subdomain]
  validation_method         = var.certificate_validation_method

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-acm-cert"
  }
}

resource "aws_lb_listener" "ShibuyaCrossing_https_listener" {
  load_balancer_arn = aws_lb.ShibuyaCrossing_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  # If validation exists, use it; otherwise use the cert ARN (apply will still require it to be ISSUED).
  certificate_arn = try(
    aws_acm_certificate_validation.ShibuyaCrossing_acm_validation.certificate_arn,
    aws_acm_certificate.ShibuyaCrossing_acm_cert.arn
  )

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ShibuyaCrossing_tg01.arn
  }
}

# Explanation: SNS is the distress beacon—when the DB dies, the galaxy (your inbox) must hear about it.
resource "aws_kms_key" "sns_cmk" {
  description             = "CMK for SNS topic encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = local.tags
}

# SNS topic
resource "aws_sns_topic" "db_incidents" {
  name              = "db-incidents"
  kms_master_key_id = aws_kms_key.sns_cmk.arn
  tags              = local.tags
}

# Email subscription
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.db_incidents.arn
  protocol  = "email"
  endpoint  = "benjam9191@gmail.com"
}


# SNS -> Lambda subscription (use the db_incidents topic you actually created)
resource "aws_sns_topic_subscription" "ShibuyaCrossing_ir_lambda_sub" {
  topic_arn = aws_sns_topic.db_incidents.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.ShibuyaCrossing_ir_lambda.arn
}


# Allow SNS to invoke Lambda (source_arn must be the same topic)
resource "aws_lambda_permission" "ShibuyaCrossing_allow_sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ShibuyaCrossing_ir_lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.db_incidents.arn
}

# Output report bucket (must exist with this exact name)
output "ShibuyaCrossing_ir_reports_bucket" {
  value = aws_s3_bucket.ShibuyaCrossing_ir_reports_bucket.bucket
}

# Explanation: Public route table = “open lanes” to the galaxy via IGW.
############################################
# Public route table
############################################
resource "aws_route_table" "ShibuyaCrossing_public_rt" {
  vpc_id = aws_vpc.ShibuyaCrossing_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ShibuyaCrossing_igw.id
  }

  tags = merge(
    local.tags,
    { Name = "${var.project_name}-public-rt" }
  )
}

# Attach ALL public subnets to the public RT
resource "aws_route_table_association" "ShibuyaCrossing_public_assoc" {
  count          = length(local.private_subnet_ids)
  subnet_id      = local.public_subnet_ids[count.index]
  route_table_id = aws_route_table.ShibuyaCrossing_public_rt.id
}

############################################
# Private route table
############################################
resource "aws_route_table" "ShibuyaCrossing_private_rt" {
  vpc_id = aws_vpc.ShibuyaCrossing_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = merge(
    local.tags,
    { Name = "${var.project_name}-private-rt" }
  )
}

# Attach ALL private subnets to the private RT
resource "aws_route_table_association" "ShibuyaCrossing_private_assoc" {
  count          = length(local.private_subnet_ids)
  subnet_id      = local.private_subnet_ids[count.index]
  route_table_id = aws_route_table.ShibuyaCrossing_private_rt.id
}

# Explanation: ShibuyaCrossing returns traffic to Sao Paulo—because doctors need answers, not one-way tunnels.
resource "aws_route" "ShibuyaCrossing_to_liberdade_route" {
  route_table_id         = aws_route_table.ShibuyaCrossing_private_rt.id
  destination_cidr_block = "10.238.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.ShibuyaCrossing_tgw.id
}

resource "aws_ec2_transit_gateway" "ShibuyaCrossing_tgw" {
  provider                        = aws.tokyo
  description                     = "ShibuyaCrossing-tgw (ShibuyaCrossing hub)"
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = {
    Name = "ShibuyaCrossing-tgw"
  }
}

resource "aws_ec2_transit_gateway" "liberdade_tgw" {
  provider                        = aws.saopaulo
  description                     = "liberdade-tgw (Sao Paulo spoke)"
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = {
    Name = "liberdade-tgw"
  }
}
