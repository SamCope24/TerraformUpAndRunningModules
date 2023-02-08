output "all_users" {
  value       = aws_iam_user.example
}

output "all_arns" {
  value = values(aws_iam_user.example)[*].arn
}

output "neo_cloudwatch_policy_arn" {
  value = one(concat(
      aws_iam_user_policy_attachment.neo_cloudwatch_full_access[*].policy_arn,
      aws_iam_user_policy_attachment.neo_cloudwatch_read_only[*].policy_arn
    )
  )
}
