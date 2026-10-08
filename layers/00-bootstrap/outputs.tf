output "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state for all layers."
  value       = aws_s3_bucket.tfstate.id
}

output "region" {
  description = "Region the state bucket lives in."
  value       = var.region
}