output "vpc_id" {
  description = "vpc id produced by this module."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "public subnet ids produced by this module."
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  description = "private subnet ids produced by this module."
  value       = { for k, s in aws_subnet.private : k => s.id }
}
