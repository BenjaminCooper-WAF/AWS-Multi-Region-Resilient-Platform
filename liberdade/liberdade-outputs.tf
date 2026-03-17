# Explanation: outputs are your mission report—what got built and where to find it.

/*
output "application_urls" {
  description = "URLs to test deployed application through the ALB"
  value       = <<EOT
Home           : https://${aws_lb.liberdade_alb.dns_name}/
Initialize DB  : https://${aws_lb.liberdade_alb.dns_name}/init
1st note (GET) : https://${aws_lb.liberdade_alb.dns_name}/add?note=first_note
2nd note (GET) : https://${aws_lb.liberdade_alb.dns_name}/add?note=blue_book_gentlemen
3rd note (GET) : https://${aws_lb.liberdade_alb.dns_name}/add?note=this_is_200k_work
4th note (GET) : https://${aws_lb.liberdade_alb.dns_name}/add?note=a_passport_is_freedom_papers
5th note (GET) : https://${aws_lb.liberdade_alb.dns_name}/add?note=lab3_is_a_success
List notes     : https://${aws_lb.liberdade_alb.dns_name}/list
EOT
}
*/

output "aws_vpc" {
  value = aws_vpc.liberdade_vpc.id
}
output "public_subnet_ids" {
  value = aws_subnet.public_liberdade[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private_liberdade[*].id
}

/*
output "db_username" {
  value = aws_db_instance.liberdade_rds.username
}

output "db_secret_name" {
  value = aws_secretsmanager_secret.db_creds.name
}

output "rds_endpoint" {
  value = aws_db_instance.liberdade_rds.endpoint
}
*/

output "sns_topic_arn" {
  value = aws_sns_topic.db_incidents.arn
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.app_logs.name
}
# Explanation: These outputs prove liberdade built private hyperspace lanes (endpoints) instead of public chaos.
output "vpce_ssm" {
  value = aws_vpc_endpoint.ssm.id
}

output "vpce_logs" {
  value = aws_vpc_endpoint.logs.id
}

output "vpce_secrets" {
  value = aws_vpc_endpoint.secrets.id
}

output "vpce_s3" {
  value = aws_vpc_endpoint.gateway.id
}

output "ec2_private_ip" {
  value = aws_instance.liberdade_ec2.private_ip
}

# Explanation: Outputs are the mission coordinates — where to point your browser and your blasters.
output "alb_dns_name" {
  value = aws_lb.liberdade_alb.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.liberdade_tg.arn
}
/*
output "acm_cert_arn" {
  value = aws_acm_certificate.liberdade_acm_cert.arn
}

output "waf_arn" {
  value = var.enable_waf ? aws_wafv2_web_acl.liberdade_waf01[0].arn : null
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.liberdade_dashboard01.dashboard_name
}

output "liberdade_waf_log_destination" {
  value = var.waf_log_destination
}

output "liberdade_waf_cw_log_group_name" {
  value = var.waf_log_destination == "cloudwatch" ? aws_cloudwatch_log_group.liberdade_waf_log_group01[0].name : null
}

output "liberdade_waf_logs_s3_bucket" {
  value = var.waf_log_destination == "s3" ? aws_s3_bucket.liberdade_waf_logs_bucket01[0].bucket : null
}

output "aws_lambda_function" {
  value = aws_lambda_function.liberdade_ir_lambda01.function_name
}
*/

output "listener_arn" {
  value = aws_lb_listener.liberdade_https_listener.arn
}
/*
output "origin_header_value" {
  value     = random_password.liberdade_origin_header_value01.result
  sensitive = true
}

output "cache_policy_api_disabled" {
  value = aws_cloudfront_cache_policy.liberdade_cache_api_disabled01.id
}

output "origin_request_policy_api" {
  value = aws_cloudfront_origin_request_policy.liberdade_orp_api01.id
}

output "cache_policy_static" {
  value = aws_cloudfront_cache_policy.liberdade_cache_static01.id
}

output "origin_request_policy_static" {
  value = aws_cloudfront_origin_request_policy.liberdade_orp_static01.id
}

output "response_headers_policy_static" {
  value = aws_cloudfront_response_headers_policy.liberdade_rsp_static01.id
}
*/
output "liberdade_transit_gateway_id" {
  value = aws_ec2_transit_gateway.liberdade_tgw.id
}

output "liberdade_transit_gateway_arn" {
  value = aws_ec2_transit_gateway.liberdade_tgw.arn
}
 
output "liberdade_sao_paulo_vpc_peering_connection_id" {
  value = aws_vpc_peering_connection.liberdade_saopaulo_peering.id
}
  
output "liberdade_vpc_id" {
  value = aws_vpc.liberdade_vpc.id
}

output "liberdade_tgw" {
  value = aws_ec2_transit_gateway.liberdade_tgw.id
}

output "tgw_peering_attachment_id" {
  value = aws_ec2_transit_gateway_peering_attachment.ShibuyaCrossing_to_liberdade.id
}

output "tgw_route_table_id" {
  value = aws_ec2_transit_gateway_route_table.liberdade_tgw_rt.id
}



output "aws_route_table" {
  value = [
    aws_route_table.liberdade_public_rt.id,
    aws_route_table.liberdade_private_rt.id
  ]
}

output "ShibuyaCrossing_sao_paulo_vpc_peering_connection_id" {
  value = aws_vpc_peering_connection.ShibuyaCrossing_liberdade_peering.id
}

output "liberdade_transit_gateway_id" {
  value = aws_ec2_transit_gateway.liberdade_tgw.id
}