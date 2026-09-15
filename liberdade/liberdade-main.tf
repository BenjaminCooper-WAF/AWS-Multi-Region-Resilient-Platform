terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28.0"
    }
    http = {
      source = "hashicorp/http"
    }
  }
}

############################
# São Paulo provider + AZs
############################

provider "aws" {
  alias  = "liberdade"
  region = "sa-east-1"
}

data "aws_availability_zones" "liberdade" {
  provider = aws.liberdade
  state    = "available"
}

data "aws_ssm_parameter" "amzn2_ami" {
  provider = aws.liberdade
  name     = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

locals {
  liberdade_vpc_cidr = "10.238.0.0/16"
  tokyo_vpc_cidr     = "10.237.0.0/16"
}

############################
# VPC
############################

resource "aws_vpc" "liberdade_vpc" {
  provider             = aws.liberdade
  cidr_block           = local.liberdade_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "liberdade-vpc"
  })
}

resource "aws_internet_gateway" "liberdade_igw" {
  provider = aws.liberdade
  vpc_id   = aws_vpc.liberdade_vpc.id

  tags = merge(local.tags, {
    Name = "${var.project_name}-liberdade-igw"
  })
}

############################
# Subnets
############################

resource "aws_subnet" "public_liberdade" {
  provider                = aws.liberdade
  count                   = 3
  vpc_id                  = aws_vpc.liberdade_vpc.id
  cidr_block              = cidrsubnet(local.liberdade_vpc_cidr, 8, count.index + 100)
  availability_zone       = data.aws_availability_zones.liberdade.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "liberdade-public-${count.index + 1}"
  })
}

resource "aws_subnet" "private_liberdade" {
  provider                = aws.liberdade
  count                   = 3
  vpc_id                  = aws_vpc.liberdade_vpc.id
  cidr_block              = cidrsubnet(local.liberdade_vpc_cidr, 8, count.index + 110)
  availability_zone       = data.aws_availability_zones.liberdade.names[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "liberdade-private-${count.index + 1}"
  })
}

############################
# Route tables
############################

resource "aws_route_table" "liberdade_public_rt" {
  provider = aws.liberdade
  vpc_id   = aws_vpc.liberdade_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.liberdade_igw.id
  }

  tags = merge(local.tags, {
    Name = "liberdade-public-rt"
  })
}

resource "aws_route_table" "liberdade_private_rt" {
  provider = aws.liberdade
  vpc_id   = aws_vpc.liberdade_vpc.id

  tags = merge(local.tags, {
    Name = "liberdade-private-rt"
  })
}

resource "aws_route_table_association" "public_liberdade" {
  provider       = aws.liberdade
  count          = 3
  subnet_id      = aws_subnet.public_liberdade[count.index].id
  route_table_id = aws_route_table.liberdade_public_rt.id
}

resource "aws_route_table_association" "private_liberdade" {
  provider       = aws.liberdade
  count          = 3
  subnet_id      = aws_subnet.private_liberdade[count.index].id
  route_table_id = aws_route_table.liberdade_private_rt.id
}

############################
# TGW
############################

resource "aws_ec2_transit_gateway" "liberdade_tgw" {
  provider                        = aws.liberdade
  amazon_side_asn                 = var.secondary_tgw_asn
  description                     = "liberdade-tgw (Sao Paulo spoke)"
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(local.tags, {
    Name = "liberdade-tgw"
  })
}

resource "aws_ec2_transit_gateway_route_table" "liberdade_tgw_rt" {
  provider           = aws.liberdade
  transit_gateway_id = aws_ec2_transit_gateway.liberdade_tgw.id

  tags = merge(local.tags, {
    Name = "liberdade-tgw-rt"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "liberdade_attach_sp_vpc" {
  provider           = aws.liberdade
  transit_gateway_id = aws_ec2_transit_gateway.liberdade_tgw.id
  vpc_id             = aws_vpc.liberdade_vpc.id
  subnet_ids = [
    aws_subnet.private_liberdade[0].id,
    aws_subnet.private_liberdade[1].id
  ]

  tags = merge(local.tags, {
    Name = "liberdade-attach-sp-vpc"
  })
}

# Explanation: the peering attachment itself is created once, by the requester side
# (aws_ec2_transit_gateway_peering_attachment.ShibuyaCrossing_to_liberdade in the root
# stack). This stack has its own state/backend, so it can't reference that resource
# directly - the attachment ID has to be passed in via var.tgw_peering_attachment_id
# (copy it from the root stack's tgw_peering_attachment output after that's applied).
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "liberdade_accept_peer" {
  provider                      = aws.liberdade
  transit_gateway_attachment_id = var.tgw_peering_attachment_id

  tags = merge(local.tags, {
    Name = "liberdade-accept-peer"
  })
}

resource "aws_route" "liberdade_to_shibuya_route" {
  provider               = aws.liberdade
  route_table_id         = aws_route_table.liberdade_private_rt.id
  destination_cidr_block = local.tokyo_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.liberdade_tgw.id
}

############################
# Endpoints
############################

resource "aws_vpc_endpoint" "liberdade_s3" {
  provider          = aws.liberdade
  vpc_id            = aws_vpc.liberdade_vpc.id
  service_name      = "com.amazonaws.sa-east-1.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [aws_route_table.liberdade_private_rt.id]

  tags = merge(local.tags, {
    Name = "${var.project_name}-liberdade-vpce-s3"
  })
}

resource "aws_vpc_endpoint" "liberdade_ssm" {
  provider            = aws.liberdade
  vpc_id              = aws_vpc.liberdade_vpc.id
  service_name        = "com.amazonaws.sa-east-1.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_liberdade[*].id
  security_group_ids  = [aws_security_group.vpce_allow_tls.id]

  tags = merge(local.tags, {
    Name = "${var.project_name}-liberdade-vpce-ssm"
  })
}

resource "aws_vpc_endpoint" "liberdade_ec2messages" {
  provider            = aws.liberdade
  vpc_id              = aws_vpc.liberdade_vpc.id
  service_name        = "com.amazonaws.sa-east-1.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_liberdade[*].id
  security_group_ids  = [aws_security_group.vpce_allow_tls.id]

  tags = merge(local.tags, {
    Name = "${var.project_name}-liberdade-vpce-ec2messages"
  })
}

resource "aws_vpc_endpoint" "liberdade_ssmmessages" {
  provider            = aws.liberdade
  vpc_id              = aws_vpc.liberdade_vpc.id
  service_name        = "com.amazonaws.sa-east-1.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_liberdade[*].id
  security_group_ids  = [aws_security_group.vpce_allow_tls.id]

  tags = merge(local.tags, {
    Name = "${var.project_name}-liberdade-vpce-ssmmessages"
  })
}

resource "aws_vpc_endpoint" "liberdade_logs" {
  provider            = aws.liberdade
  vpc_id              = aws_vpc.liberdade_vpc.id
  service_name        = "com.amazonaws.sa-east-1.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_liberdade[*].id
  security_group_ids  = [aws_security_group.vpce_allow_tls.id]

  tags = merge(local.tags, {
    Name = "${var.project_name}-liberdade-vpce-logs"
  })
}

resource "aws_vpc_endpoint" "liberdade_secrets" {
  provider            = aws.liberdade
  vpc_id              = aws_vpc.liberdade_vpc.id
  service_name        = "com.amazonaws.sa-east-1.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_liberdade[*].id
  security_group_ids  = [aws_security_group.vpce_allow_tls.id]

  tags = merge(local.tags, {
    Name = "${var.project_name}-liberdade-vpce-secrets"
  })
}

resource "aws_vpc_endpoint" "liberdade_kms" {
  provider            = aws.liberdade
  vpc_id              = aws_vpc.liberdade_vpc.id
  service_name        = "com.amazonaws.sa-east-1.kms"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_liberdade[*].id
  security_group_ids  = [aws_security_group.vpce_allow_tls.id]

  tags = merge(local.tags, {
    Name = "${var.project_name}-liberdade-vpce-kms"
  })
}

############################
# Instance + target group
############################

resource "aws_instance" "liberdade_ec2" {
  provider                    = aws.liberdade
  ami                         = data.aws_ssm_parameter.amzn2_ami.value
  instance_type               = local.instance_type
  # Explanation: SSH key-pair access dropped after the leaked ec2-lab-app.pem
  # incident - this instance already has SSM Session Manager wired up (IAM role +
  # interface endpoints), so no key pair is needed at all.
  key_name                    = null
  subnet_id                   = aws_subnet.private_liberdade[0].id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false
  user_data_replace_on_change = true
  user_data                   = file("${path.module}/user_data.sh")
  monitoring                  = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-liberdade-ec2-app"
  })
}

# Explanation: target group protocol/port must match what the target attachment
# and the EC2 app actually serve (plain HTTP on 80) - the ALB terminates TLS from
# the earlier redirect listener, the instance behind it doesn't.
resource "aws_lb_target_group" "liberdade_tg01" {
  provider    = aws.liberdade
  name        = "liberdade-tg01"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.liberdade_vpc.id
  target_type = "instance"

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

  tags = merge(local.tags, {
    Name = "liberdade-tg01"
  })
}

resource "aws_lb_target_group_attachment" "liberdade_tg_attach01" {
  provider         = aws.liberdade
  target_group_arn = aws_lb_target_group.liberdade_tg01.arn
  target_id        = aws_instance.liberdade_ec2.id
  port             = 80
}

resource "aws_lb" "liberdade_alb" {
  provider           = aws.liberdade
  name               = "liberdade-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.liberdade_alb_sg.id]
  subnets            = aws_subnet.public_liberdade[*].id

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs ? [1] : []
    content {
      bucket  = aws_s3_bucket.liberdade_alb_logs_bucket.bucket
      prefix  = var.alb_access_logs_prefix
      enabled = var.enable_alb_access_logs
    }
  }

  depends_on = [
    aws_s3_bucket.liberdade_alb_logs_bucket,
    aws_s3_bucket_public_access_block.liberdade_alb_logs_pab01,
    aws_s3_bucket_ownership_controls.liberdade_alb_logs_owner,
    aws_s3_bucket_policy.liberdade_alb_logs_policy
  ]

  tags = merge(local.tags, {
    Name = "liberdade-alb"
  })
}

# Explanation: no ACM cert/domain exists for liberdade yet, so this stays HTTP-only
# for now (forwarding straight to the target group) instead of redirecting to a
# :443 listener that doesn't exist. Add an HTTPS listener + cert later if needed.
resource "aws_lb_listener" "liberdade_http_listener" {
  provider          = aws.liberdade
  load_balancer_arn = aws_lb.liberdade_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.liberdade_tg01.arn
  }
}

resource "aws_security_group" "liberdade_alb_sg" {
  provider    = aws.liberdade
  name        = "liberdade-alb-sg"
  description = "ALB security group (liberdade)"
  vpc_id      = aws_vpc.liberdade_vpc.id

  tags = merge(local.tags, {
    Name = "liberdade-alb-sg"
  })
}

resource "aws_security_group_rule" "liberdade_alb_ingress_http" {
  provider          = aws.liberdade
  type              = "ingress"
  security_group_id = aws_security_group.liberdade_alb_sg.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "liberdade_alb_egress_to_ec2_http" {
  provider                 = aws.liberdade
  type                     = "egress"
  security_group_id        = aws_security_group.liberdade_alb_sg.id
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ec2_sg.id
}

resource "aws_security_group" "ec2_sg" {
  provider    = aws.liberdade
  name        = "${var.project_name}-liberdade-ec2-sg"
  description = "EC2 app security group (liberdade)"
  vpc_id      = aws_vpc.liberdade_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.liberdade_alb_sg.id]
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

  tags = merge(local.tags, {
    Name = "${var.project_name}-liberdade-ec2-sg"
  })
}

resource "aws_security_group" "vpce_allow_tls" {
  provider    = aws.liberdade
  name        = "${var.project_name}-liberdade-vpce-allow-tls"
  description = "Allow TLS from inside VPC to interface endpoints"
  vpc_id      = aws_vpc.liberdade_vpc.id

  tags = merge(local.tags, {
    Name = "${var.project_name}-liberdade-vpce-allow-tls"
  })
}

resource "aws_vpc_security_group_ingress_rule" "vpce_tls_ipv4" {
  provider           = aws.liberdade
  security_group_id  = aws_security_group.vpce_allow_tls.id
  cidr_ipv4          = aws_vpc.liberdade_vpc.cidr_block
  from_port          = 443
  to_port            = 443
  ip_protocol        = "tcp"
  description        = "TLS from VPC IPv4"
}

resource "aws_vpc_security_group_egress_rule" "vpce_all_ipv4" {
  provider           = aws.liberdade
  security_group_id  = aws_security_group.vpce_allow_tls.id
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol        = "-1"
  description        = "All outbound IPv4"
}

resource "aws_iam_role" "ec2_role" {
  provider = aws.liberdade
  name     = "${var.project_name}-liberdade-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  provider   = aws.liberdade
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  provider = aws.liberdade
  name     = "${var.project_name}-liberdade-ec2-profile"
  role     = aws_iam_role.ec2_role.name
}

############################
# S3 bucket for ALB access logs
############################

resource "aws_s3_bucket" "liberdade_alb_logs_bucket" {
  provider      = aws.liberdade
  bucket        = "liberdade-alb-logs-${data.aws_caller_identity.saopaulo.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "liberdade_alb_logs_versioning" {
  provider = aws.liberdade
  bucket   = aws_s3_bucket.liberdade_alb_logs_bucket.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "liberdade_alb_logs_encryption" {
  provider = aws.liberdade
  count    = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.liberdade_alb_logs_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "liberdade_alb_logs_pab01" {
  provider = aws.liberdade
  count    = var.enable_alb_access_logs ? 1 : 0

  bucket                  = aws_s3_bucket.liberdade_alb_logs_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "liberdade_alb_logs_owner" {
  provider = aws.liberdade
  bucket   = aws_s3_bucket.liberdade_alb_logs_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_policy" "liberdade_alb_logs_policy" {
  provider = aws.liberdade
  count    = var.enable_alb_access_logs ? 1 : 0
  bucket   = aws_s3_bucket.liberdade_alb_logs_bucket.id

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
        Resource = "arn:aws:s3:::${aws_s3_bucket.liberdade_alb_logs_bucket.bucket}/${var.alb_access_logs_prefix != "" ? "${var.alb_access_logs_prefix}/" : ""}AWSLogs/${data.aws_caller_identity.saopaulo.account_id}/*"
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.liberdade_alb_logs_bucket.bucket}",
          "arn:aws:s3:::${aws_s3_bucket.liberdade_alb_logs_bucket.bucket}/*"
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