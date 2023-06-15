output "application_url" {
  value = aws_alb.harsh_load_balancer.dns_name
}