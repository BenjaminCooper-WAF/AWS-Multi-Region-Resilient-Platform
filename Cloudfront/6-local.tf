locals {
  project_name               = "Tokyo"
  vpc_cidr                   = "10.237.0.0/16"
  instance_type              = "t3.micro"
  db_instance_class          = "db.t3.micro"
  db_name                    = "tokyodb"
  db_username                = "admin"
  my_ip_cidr                 = "${chomp(data.http.my_public-ip.response_body)}/32"
  region                     = "eu-west-2"
  secret_name                = "lab/rds/mysql"
  zone_name                  = "passportpookie.click"
  hosted_zone_id             = "Z09361711HDESSBG6MZ22"
  fqdn                       = "passportpookie.click"
  app_subdomain              = "app.passportpookie.click"
  passportpookie_zone_id     = local.hosted_zone_id
  public_subnet_ids          = aws_subnet.public_lab2[*].id
  private_subnet_ids         = aws_subnet.private_lab2[*].id
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



