terraform {
  backend "s3" {
    bucket = "terraform-state-961341540291-sa-east-1"
    key    = "terraform.tfstate"
    region = "sa-east-1"
  }
}