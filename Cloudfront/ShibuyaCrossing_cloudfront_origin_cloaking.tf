# Explanation: ShibuyaCrossing only opens the hangar to CloudFront — everyone else gets the Wookiee roar.
data "aws_ec2_managed_prefix_list" "ShibuyaCrossing_cf_origin_facing01" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# Explanation: Only CloudFront origin-facing IPs may speak to the ALB — direct-to-ALB attacks die here.
resource "aws_security_group_rule" "ShibuyaCrossing_alb_ingress_cf44301" {
  type              = "ingress"
  security_group_id = aws_security_group.ShibuyaCrossing_alb_sg.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"

  prefix_list_ids = [
    data.aws_ec2_managed_prefix_list.ShibuyaCrossing_cf_origin_facing01.id
  ]
}

# Explanation: This is ShibuyaCrossing’s secret handshake — if the header isn’t present, you don’t get in.
resource "random_password" "ShibuyaCrossing_origin_header_value01" {
  length  = 32
  special = false
}

# Explanation: ALB checks for ShibuyaCrossing’s secret growl — no growl, no service.
resource "aws_lb_listener_rule" "ShibuyaCrossing_require_origin_header01" {
  listener_arn = aws_lb_listener.ShibuyaCrossing_https_listener.arn
  priority     = 10

  # If header matches → forward to TG Else → fixed 403

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ShibuyaCrossing_tg01.arn
  }

  condition {
    http_header {
      http_header_name = "X-ShibuyaCrossing-Growl"
      values           = [var.origin_secret]
    }
  }
}

# Explanation: If you don’t know the growl, you get a 403 — ShibuyaCrossing does not negotiate.
resource "aws_lb_listener_rule" "ShibuyaCrossing_default_block01" {
  listener_arn = aws_lb_listener.ShibuyaCrossing_https_listener.arn
  priority     = 99

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  condition {
    path_pattern { values = ["*"] }
  }
}
