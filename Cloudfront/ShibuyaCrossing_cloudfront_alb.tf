# Explanation: CloudFront is the only public doorway — lab3 stands behind it with private infrastructure.
resource "aws_cloudfront_distribution" "lab3_cf01" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name}-cf01"
  default_root_object = "index.html"

  origin {
    origin_id   = "${var.project_name}-alb-origin01"
    domain_name = aws_lb.lab3_alb.dns_name


    custom_header {
      name  = "x-lab3-growl"
      value = var.origin_secret
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Explanation: CloudFront whispers the secret growl — the ALB only trusts this.
    custom_header {
      name  = "X-lab3"
      value = random_password.lab3_origin_header_value01.result
    }
  }

  origin {
    origin_id   = "${var.project_name}-alb-origin02"
    domain_name = aws_lb.lab3_alb.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-lab3"
      value = random_password.lab3_origin_header_value01.result
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
  web_acl_id = aws_wafv2_web_acl.lab3_cf_waf01.arn

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



