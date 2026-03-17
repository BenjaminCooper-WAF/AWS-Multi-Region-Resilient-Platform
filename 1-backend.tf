terraform {
  backend "s3" {
    bucket  = "terraform-state-961341540291-ap-northeast-1"
    key     = "terraform.tfstate"
    encrypt = true
    profile = "default"
    region  = "ap-northeast-1"
  }
}