data "http" "my_public_ip" {
  url = "http://ipv4.icanhazip.com"
}

locals {
  project_name = var.project_name
  instance_type = "t3.micro"

  my_ip_cidr = "${chomp(data.http.my_public_ip.response_body)}/32"

  public_subnet_ids  = aws_subnet.public_saopaulo[*].id
  private_subnet_ids = aws_subnet.private_saopaulo[*].id

  tags = {
    project     = var.project_name
    environment = "lab3"
    ManagedBy   = "Terraform"
  }
}
