output "vpc_id" {
  description = "Provisioned AWS VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "Provisioned AWS VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs across us-east-2a and us-east-2b"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs across us-east-2a and us-east-2b"
  value       = aws_subnet.private[*].id
}
