############################################
# Lab 2B-Honors+ - Optional invalidation action (run on demand)
############################################

# Explanation: This is ShibuyaCrossing’s “break glass” lever — use it sparingly or the bill will bite.
action "aws_cloudfront_create_invalidation" "ShibuyaCrossing_invalidate_index01" {
  config {
    distribution_id = aws_cloudfront_distribution.ShibuyaCrossing_cf01.id

    paths = ["/static/*"]
  }
}


