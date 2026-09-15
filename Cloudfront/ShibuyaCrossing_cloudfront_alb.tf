# Explanation: this stack has its own state/backend, separate from the root
# (Tokyo) stack that creates the ALB. It looks the ALB up by name instead of
# referencing it directly, since cross-state resource references aren't possible.
data "aws_lb" "ShibuyaCrossing_alb" {
  name = "ShibuyaCrossing-alb"
}

# Explanation: CloudFront is the only public doorway — lab3 stands behind it with private infrastructure.
resource "aws_cloudfront_distribution" "ShibuyaCrossing_cf01" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name}-cf01"
  default_root_object = "index.html"

  origin {
    origin_id   = "${var.project_name}-alb-origin01"
    domain_name = data.aws_lb.ShibuyaCrossing_alb.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Explanation: CloudFront whispers the secret growl — the ALB only trusts this.
    # Header name/value must match what the ALB listener rule in
    # ShibuyaCrossing_cloudfront_origin_cloaking.tf actually checks for.
    custom_header {
      name  = var.origin_secret
      value = random_password.ShibuyaCrossing_origin_header_value01.result
    }
  }

  origin {
    origin_id   = "${var.project_name}-alb-origin02"
    domain_name = data.aws_lb.ShibuyaCrossing_alb.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = var.origin_secret
      value = random_password.ShibuyaCrossing_origin_header_value01.result
    }
  }

  origin_group {
    origin_id = "${var.project_name}-alb-origin-group"

    failover_criteria {
      status_codes = [500, 502, 503, 504]
    }

    member {
      origin_id = "${var.project_name}-alb-origin01"
    }

    member {
      origin_id = "${var.project_name}-alb-origin02"
    }
  }

  default_cache_behavior {
    target_origin_id       = "${var.project_name}-alb-origin-group"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    # TODO: students choose cache policy / origin request policy for their app type
    # For APIs, typically forward all headers/cookies/querystrings.
    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies { forward = "all" }
    }
  }

  # Explanation: Attach WAF at the edge — now WAF moved to CloudFront.
  web_acl_id = aws_wafv2_web_acl.ShibuyaCrossing_cf_waf01.arn

  # TODO: students set aliases for lab3-growl.com and app.lab3-growl.com
  aliases = [
    "passportpookie.click",
    "app.passportpookie.click"
  ]

  # TODO: students must use ACM cert in us-east-1 for CloudFront
  viewer_certificate {
    acm_certificate_arn      = var.cloudfront_acm_cert_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}
