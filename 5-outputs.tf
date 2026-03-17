# Explanation: outputs are your mission report—what got built and where to find it.


output "application_urls" {
  description = "URLs to test deployed application through the ALB"
  value       = <<EOT
Home           : https://${aws_lb.ShibuyaCrossing_alb.dns_name}/
Initialize DB  : https://${aws_lb.ShibuyaCrossing_alb.dns_name}/init
1st note (GET) : https://${aws_lb.ShibuyaCrossing_alb.dns_name}/add?note=first_note
2nd note (GET) : https://${aws_lb.ShibuyaCrossing_alb.dns_name}/add?note=blue_book_gentlemen
3rd note (GET) : https://${aws_lb.ShibuyaCrossing_alb.dns_name}/add?note=this_is_200k_work
4th note (GET) : https://${aws_lb.ShibuyaCrossing_alb.dns_name}/add?note=a_passport_is_freedom_papers
5th note (GET) : https://${aws_lb.ShibuyaCrossing_alb.dns_name}/add?note=lab3_is_a_success
List notes     : https://${aws_lb.ShibuyaCrossing_alb.dns_name}/list
EOT
}

output "aws_vpc" {
  value = aws_vpc.ShibuyaCrossing_vpc.id
}

output "vpc_cidr" {
  value = aws_vpc.ShibuyaCrossing_vpc.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public_ShibuyaCrossing[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private_ShibuyaCrossing[*].id
}


output "db_username" {
  value = aws_db_instance.lab_rds.username
}


output "db_secret_name" {
  value = aws_secretsmanager_secret.db_creds.name
}

output "rds_endpoint" {
  value = aws_db_instance.lab_rds.endpoint
}

output "sns_topic_arn" {
  value = aws_sns_topic.db_incidents.arn
}

output "cloudwatch_log_metric_filter_name" {
  value = aws_cloudwatch_log_metric_filter.db_connection_errors.id
}


output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.app_logs.name
}
# Explanation: These outputs prove ShibuyaCrossing built private hyperspace lanes (endpoints) instead of public chaos.
output "vpce_ssm" {
  value = aws_vpc_endpoint.ssm.id
}

output "vpce_logs" {
  value = aws_vpc_endpoint.logs.id
}

output "vpce_secrets" {
  value = aws_vpc_endpoint.secrets.id
}
/*
output "vpce_s3" {
  value = aws_vpc_endpoint.gateway.id
}
*/
output "ec2_private_ip" {
  value = aws_instance.ShibuyaCrossing_ec2.private_ip
}

# Explanation: Outputs are the mission coordinates — where to point your browser and your blasters.
output "alb_dns_name" {
  value = aws_lb.ShibuyaCrossing_alb.dns_name
}

output "ShibuyaCrossing_app_fqdn" {
  value = "${var.app_subdomain}.${var.domain_name}"
}

output "target_group_arn" {
  value = aws_lb_target_group.ShibuyaCrossing_tg01.arn
}

output "acm_cert_arn" {
  value = aws_acm_certificate.ShibuyaCrossing_acm_cert.arn
}

output "waf_arn" {
  value = var.enable_waf ? aws_wafv2_web_acl.ShibuyaCrossing_waf01[0].arn : null
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.ShibuyaCrossing_dashboard01.dashboard_name
}

output "ShibuyaCrossing_app_url_https" {
  value = "https://${var.app_subdomain}.${var.domain_name}"
}

output "ShibuyaCrossing_waf_log_destination" {
  value = var.waf_log_destination
}

output "ShibuyaCrossing_waf_cw_log_group_name" {
  value = var.waf_log_destination == "cloudwatch" ? aws_cloudwatch_log_group.ShibuyaCrossing_waf_log_group01[0].name : null
}

output "ShibuyaCrossing_waf_logs_s3_bucket" {
  value = var.waf_log_destination == "s3" ? aws_s3_bucket.ShibuyaCrossing_waf_logs_bucket01[0].bucket : null
}

output "aws_lambda_function" {
  value = aws_lambda_function.ShibuyaCrossing_ir_lambda.function_name
}

output "listener_arn" {
  value = aws_lb_listener.ShibuyaCrossing_https_listener.arn
}
/*
output "origin_header_value" {
  value     = random_password.ShibuyaCrossing_origin_header_value01.result
  sensitive = true
}

output "cache_policy_api_disabled" {
  value = aws_cloudfront_cache_policy.ShibuyaCrossing_cache_api_disabled01.id
}

output "origin_request_policy_api" {
  value = aws_cloudfront_origin_request_policy.ShibuyaCrossing_orp_api01.id
}

output "cache_policy_static" {
  value = aws_cloudfront_cache_policy.ShibuyaCrossing_cache_static01.id
}

output "origin_request_policy_static" {
  value = aws_cloudfront_origin_request_policy.ShibuyaCrossing_orp_static01.id
}

output "response_headers_policy_static" {
  value = aws_cloudfront_response_headers_policy.ShibuyaCrossing_rsp_static01.id
}
*/
output "transit_gateway" {
  value = [
    aws_ec2_transit_gateway.ShibuyaCrossing_tgw.id,
  ]
}

output "ShibuyaCrossing_transit_gateway_arn" {
  value = aws_ec2_transit_gateway.ShibuyaCrossing_tgw.arn
}

/*output "ShibuyaCrossing_sao_paulo_vpc_peering_connection_id" {
  value = aws_vpc_peering_connection.ShibuyaCrossing_liberdade_peering.id
}
*/

output "tgw_peering_attachment" {
  value = aws_ec2_transit_gateway_peering_attachment.ShibuyaCrossing_to_liberdade.id
}

output "tgw_route_table" {
  value = aws_ec2_transit_gateway_route_table.ShibuyaCrossing_tgw_rt.id
}

output "aws_security_group" {
  value = aws_security_group.ShibuyaCrossing_alb_sg.id
}

output "aws_security_group_rule" {
  value = [
    aws_security_group_rule.alb_ingress.id,
    aws_security_group_rule.alb_ingress_https.id,
    aws_security_group_rule.alb_egress_to_ec2_http.id
  ]
}

output "route_table" {
  value = [
    aws_route_table.ShibuyaCrossing_public_rt.id,
    aws_route_table.ShibuyaCrossing_private_rt.id,
    /*
    aws_route_table.liberdade_public_rt.id,
    aws_route_table.liberdade_private_rt.id
    */
  ]
}


output "aws_cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.app_logs.name
}


output "aws_cloudwatch_metric_alarm" {
  value = [
    aws_cloudwatch_metric_alarm.ShibuyaCrossing_alb_5xx_alarm.alarm_name,
    /*aws_cloudwatch_metric_alarm.ShibuyaCrossing_db_connection_errors_alarm.alarm_name*/
  ]
}

output "aws_s3_bucket" {
  value = [
    aws_s3_bucket.ShibuyaCrossing_alb_logs_bucket.bucket,
    aws_s3_bucket.ShibuyaCrossing_ir_reports_bucket.bucket,
    /*aws_s3_bucket_ownership_controls.ShibuyaCrossing_alb_logs_owner,*/
    var.enable_waf && var.waf_log_destination == "s3" ? aws_s3_bucket.ShibuyaCrossing_waf_logs_bucket01[0].bucket : null
  ]
}

output "aws_db_subnet_group" {
  value = aws_db_subnet_group.lab_rds.name
}