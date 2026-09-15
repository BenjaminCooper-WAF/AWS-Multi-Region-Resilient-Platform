# Explanation: outputs are your mission report—what got built and where to find it.

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.ShibuyaCrossing_cf01.id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.ShibuyaCrossing_cf01.domain_name
}

output "ShibuyaCrossing_app_fqdn" {
  value = var.app_subdomain
}

output "ShibuyaCrossing_app_url_https" {
  value = "https://${var.app_subdomain}"
}

output "cf_waf_arn" {
  value = aws_wafv2_web_acl.ShibuyaCrossing_cf_waf01.arn
}

output "listener_arn" {
  value = data.aws_lb_listener.ShibuyaCrossing_https_listener.arn
}

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

# TODO: the following used to reference root-stack-only resources (TGW, Lambda,
# regional WAF logging, CloudWatch dashboard, aws_vpc_peering_connection which was
# never actually used anywhere - TGW peering is used instead) that don't exist in
# this stack. Re-add as data-source lookups if this stack ever needs to surface them.
