#################################################
#1) Cache policy for static content (aggressive)
##############################################################

# Explanation: Static files are the easy win—ShibuyaCrossing caches them like hyperfuel for speed.
resource "aws_cloudfront_cache_policy" "ShibuyaCrossing_cache_static01" {
  name        = "${var.project_name}-cache-static01"
  comment     = "Aggressive caching for /static/*"
  default_ttl = 86400    # 1 day
  max_ttl     = 31536000 # 1 year
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    # Explanation: Static should not vary on cookies—ShibuyaCrossing refuses to cache 10,000 versions of a PNG.
    cookies_config { cookie_behavior = "none" }

    # Explanation: Static should not vary on query strings (unless you do versioning); students can change later.
    query_strings_config { query_string_behavior = "none" }

    # Explanation: Keep headers out of cache key to maximize hit ratio.
    headers_config { header_behavior = "none" }

    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

############################################################
#2) Cache policy for API (safe default: caching disabled)
##############################################################

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Explanation: APIs are dangerous to cache by accident—ShibuyaCrossing disables caching until proven safe.
resource "aws_cloudfront_cache_policy" "ShibuyaCrossing_cache_api_disabled01" {
  name        = "ShibuyaCrossing-api-caching-disabled"
  comment     = "Disable caching for dynamic API traffic"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
  }
}

############################################################
#3) Origin request policy for API (forward what origin needs)
##############################################################


# Explanation: Origins need context—ShibuyaCrossing forwards what the app needs without polluting the cache key.
resource "aws_cloudfront_origin_request_policy" "ShibuyaCrossing_orp_api01" {
  name = "ShibuyaCrossing-orp-api01"
  cookies_config {
    cookie_behavior = "all"
  }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Host"] # Add other headers your API needs here
    }
  }
  query_strings_config {
    query_string_behavior = "all"
  }
}

##################################################################
# 4) Origin request policy for static (minimal)
##############################################################


# Explanation: Static origins need almost nothing—ShibuyaCrossing forwards minimal values for maximum cache sanity.
resource "aws_cloudfront_origin_request_policy" "ShibuyaCrossing_orp_static01" {
  name    = "${var.project_name}-orp-static01"
  comment = "Minimal forwarding for static assets"

  cookies_config { cookie_behavior = "none" }
  query_strings_config { query_string_behavior = "none" }
  headers_config { header_behavior = "none" }
}

##############################################################
# 5) Response headers policy (optional but nice)
##############################################################

# Explanation: Make caching intent explicit—ShibuyaCrossing stamps Cache-Control so humans and CDNs agree.
resource "aws_cloudfront_response_headers_policy" "ShibuyaCrossing_rsp_static01" {
  name    = "${var.project_name}-rsp-static01"
  comment = "Add explicit Cache-Control for static content"

  custom_headers_config {
    items {
      header   = "Cache-Control"
      override = true
      value    = "public, max-age=86400, immutable"
    }
  }
}
