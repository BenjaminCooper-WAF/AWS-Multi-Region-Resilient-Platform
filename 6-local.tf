locals {
  project_name               = "lab3"
  vpc_cidr                   = "10.237.0.0/16"
  instance_type              = "t3.micro"
  db_instance_class          = "db.t3.micro"
  db_name                    = "Schdb"
  db_username                = "admin"
  primary_region             = "ap-northeast-1"
  secondary_region           = "sa-east-1"
  primary_vpc_cidr           = "10.237.0.0/16"
  secondary_vpc_cidr         = "10.238.0.0/16"
  primary_tgw_asn            = 27512
  secondary_tgw_asn          = 27513
  my_ip_cidr                 = "${chomp(data.http.my_public_ip.response_body)}/32"
  region                     = "ap-northeast-1"
  secret_name                = "lab/rds/mysql"
  zone_name                  = "passportpookie.click"
  hosted_zone_id             = "Z09361711HDESSBG6MZ22"
  fqdn                       = "passportpookie.click"
  app_subdomain              = "app.passportpookie.click"
  passportpookie_zone_id     = var.manage_route53_in_terraform ? aws_route53_zone.passportpookie[0].zone_id : data.aws_route53_zone.passportpookie_existing[0].zone_id
  secret_arn_guess           = "arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:${var.secrets_manager}/rds/mysql*"
  public_subnet_ids          = aws_subnet.public_ShibuyaCrossing[*].id
  private_subnet_ids         = aws_subnet.private_ShibuyaCrossing[*].id
  caching_disabled_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"


  interface_endpoints = {
    ssm         = "com.amazonaws.eu-west-2.ssm"
    ec2messages = "com.amazonaws.eu-west-2.ec2messages"
    ssmmessages = "com.amazonaws.eu-west-2.ssmmessages"
    logs        = "com.amazonaws.eu-west-2.logs"
    secrets     = "com.amazonaws.eu-west-2.secretsmanager"
    kms         = "com.amazonaws.eu-west-2.kms"
  }

  gateway_endpoints = {
    s3 = "com.amazonaws.eu-west-2.s3"
  }

  tags = {
    project     = local.project_name
    environment = "lab"
    ManagedBy   = "Terraform"
  }
}



