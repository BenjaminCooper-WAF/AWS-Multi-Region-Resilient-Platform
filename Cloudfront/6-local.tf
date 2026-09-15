locals {
  project_name               = "lab3"
  hosted_zone_id             = "Z09361711HDESSBG6MZ22"
  caching_disabled_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

  tags = {
    project     = local.project_name
    environment = "lab"
    ManagedBy   = "Terraform"
  }
}
