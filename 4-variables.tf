data "aws_caller_identity" "current" {
  provider = aws.tokyo
}

data "aws_availability_zones" "available" {
  provider = aws.tokyo
  state    = "available"
}

data "http" "my_public_ip" {
  url = "http://ipv4.icanhazip.com"
}

data "aws_region" "current" {
  provider = aws.tokyo
}

data "aws_elb_service_account" "main" {
  provider = aws.tokyo
}

variable "primary_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "second_region" {
  description = "Secondary AWS Region for cross-region resources."
  type        = string
  default     = "sa_east_1"
}

variable "ShibuyaCrossing_vpc_cidr" {
  type    = string
  default = "10.237.0.0/16"
}

variable "liberdade_vpc_cidr" {
  type    = string
  default = "10.238.0.0/16"
}

variable "Tgw_subnet_cidr" {
  type    = string
  default = "10.237.100.0/28"
}

variable "origin_targat_id" {
  type    = string
  default = "null"
}

variable "primary_tgw_asn" {
  type    = number
  default = 27512
}

variable "secondary_tgw_asn" {
  type    = number
  default = 27513
}

variable "project_name" {
  description = "Same prefix name for all resources."
  type        = string
  default     = "lab3"
}

variable "aws_key_pair_name" {
  description = "Name of the keypair to use for EC2 instances."
  type        = string
  default     = "ec2-lab-app"
}

variable "ec2_instance_type" {
  description = "EC2 instance size for the app."
  type        = string
  default     = "t3.micro"
}

variable "db_engine" {
  description = "RDS engine."
  type        = string
  default     = "mysql"
}

variable "secrets_manager" {
  description = "secrets Manager secret name for DB credentials."
  type        = string
  default     = "lab/rds/mysql"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "tokyodb" # Students can change
}

variable "db_username" {
  description = "DB master username (students should use Secrets Manager in 1B/1C)."
  type        = string
  default     = "admin" # TODO: student supplies
}

variable "db_password" {
  description = "DB master password (DO NOT hardcode in real life; for lab only)."
  type        = string
  sensitive   = true
  default     = "WATER&oil92**" # TODO: student supplies
}

variable "sns_email_endpoint" {
  description = "Email for SNS subscription (PagerDuty simulation)."
  type        = string
  default     = "benjam9191@gmail.com" # TODO: student supplies
}


variable "domain_name" {
  description = "Base domain students registered (e.g., chewbacca-growl.com)."
  type        = string
  default     = "passportpookie.click"
}

variable "app_subdomain" {
  description = "App hostname prefix (e.g., app.chewbacca-growl.com)."
  type        = string
  default     = "app.passportpookie.click"
}

variable "certificate_validation_method" {
  description = "ACM validation method. Students can do DNS (Route53) or EMAIL."
  type        = string
  default     = "DNS"
}

variable "enable_waf" {
  description = "Toggle WAF creation."
  type        = bool
  default     = true
}

variable "alb_5xx_threshold" {
  description = "Alarm threshold for ALB 5xx count."
  type        = number
  default     = 10
}

variable "alb_5xx_period_seconds" {
  description = "CloudWatch alarm period."
  type        = number
  default     = 300
}

variable "alb_5xx_evaluation_periods" {
  description = "Evaluation periods for alarm."
  type        = number
  default     = 1
}

variable "manage_route53_in_terraform" {
  description = "Set to true if Terraform will manage Route53 records."
  type        = bool
  default     = false
}
/*
variable "waf_log_destination" {
  description = "S3 bucket name for WAF logs."
  type        = string
  default     = "lab1cbs-waf-logs"
}

variable "enable_waf_logs" {
  description = "Toggle WAF logging."
  type        = bool
  default     = false
}


variable "waf_log_retention_days" {
  description = "Retention period for WAF logs (days)."
  type        = number
  default     = 30
}
*/

variable "enable_alb_access_logs" {
  description = "Enable ALB access logs."
  type        = bool
  default     = true
}

variable "alb_access_logs_prefix" {
  description = "S3 prefix for ALB logs."
  type        = string
  default     = "alb-access-logs"
}

variable "hosted_zone_id" {
  type = string
}

variable "waf_log_destination" {
  description = "Choose ONE destination per WebACL: cloudwatch | s3 | firehose"
  type        = string
  default     = "cloudwatch"
}

variable "waf_log_retention_days" {
  description = "Retention for WAF CloudWatch log group."
  type        = number
  default     = 14
}

variable "enable_waf_sampled_requests_only" {
  description = "If true, students can optionally filter/redact fields later. (Placeholder toggle.)"
  type        = bool
  default     = false
}

variable "origin_secret" {
  description = "Name of the custom header for CloudFront to ALB authentication."
  type        = string
  default     = "x-lab3secret"
}

variable "cloudfront_acm_cert_arn" {
  type        = string
  description = "ACM certificate ARN in us-east-1 for CloudFront"
  default     = "arn:aws:acm:us-east-1:961341540291:certificate/049554e8-4912-4a5a-8fa3-74e425d0911f"
}











