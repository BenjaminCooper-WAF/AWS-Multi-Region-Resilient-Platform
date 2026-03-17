############################################
# Lab 2B-Honors - Origin Driven Caching (Managed Policies)
############################################

# Explanation: ShibuyaCrossing uses AWS-managed policies—battle-tested configs so students learn the real names.
data "aws_cloudfront_cache_policy" "ShibuyaCrossing_use_origin_cache_headers01" {
  name = "UseOriginCacheControlHeaders"
}

# Explanation: Same idea, but includes query strings in the cache key when your API truly varies by them.
data "aws_cloudfront_cache_policy" "ShibuyaCrossing_use_origin_cache_headers_qs01" {
  name = "UseOriginCacheControlHeaders-QueryStrings"
}

# Explanation: Origin request policies let us forward needed stuff without polluting the cache key.
# (Origin request policies are separate from cache policies.)
data "aws_cloudfront_origin_request_policy" "ShibuyaCrossing_orp_all_viewer01" {
  name = "Managed-AllViewer"
}

data "aws_cloudfront_origin_request_policy" "ShibuyaCrossing_orp_all_viewer_except_host01" {
  name = "Managed-AllViewerExceptHostHeader"
}

############################################
# Lab 2B-Honors - CloudFront Distribution
############################################

resource "aws_cloudfront_distribution" "ShibuyaCrossing_honors_distribution" {
  enabled = true

  origin {
    domain_name = aws_lb.ShibuyaCrossing_alb.dns_name
    origin_id   = "${var.project_name}-alb-origin01"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Explanation: Default behavior is conservative—ShibuyaCrossing assumes dynamic until proven static.
  default_cache_behavior {
    target_origin_id       = "${var.project_name}-alb-origin01"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = aws_cloudfront_cache_policy.ShibuyaCrossing_cache_api_disabled01.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.ShibuyaCrossing_orp_all_viewer01.id
  }

  # Explanation: Static behavior is the speed lane—ShibuyaCrossing caches it hard for performance.
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "${var.project_name}-alb-origin01"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = local.caching_disabled_policy_id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.ShibuyaCrossing_orp_api01.id
  }

  ############################################
  # Lab 2B-Honors - A) /api/public-feed = origin-driven caching
  ############################################

  # Explanation: Public feed is cacheable—but only if the origin explicitly says so. ShibuyaCrossing demands consent.
  ordered_cache_behavior {
    path_pattern           = "/api/public-feed"
    target_origin_id       = "${var.project_name}-alb-origin01"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    # Honor Cache-Control from origin (and default to not caching without it).
    cache_policy_id = local.caching_disabled_policy_id

    # Forward what origin needs. Keep it tight: don't forward everything unless required.
    origin_request_policy_id = aws_cloudfront_origin_request_policy.ShibuyaCrossing_orp_api01.id
  }

  ############################################
  # Lab 2B-Honors - B) /api/* = still safe default (no caching)
  ############################################

  # Explanation: Everything else under /api is dangerous by default—ShibuyaCrossing disables caching until proven safe.
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "${var.project_name}-alb-origin01"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = local.caching_disabled_policy_id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.ShibuyaCrossing_orp_api01.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
