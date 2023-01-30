output "user_arn" {
  value       = aws_iam_user.example.arn
  description = "The ARN for the created IAM user"
}