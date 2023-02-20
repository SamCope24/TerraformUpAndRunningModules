data "aws_caller_identity" "self" {}

data "aws_iam_policy_document" "cmk_admin_policy" {
    statement {
      effect = "Allow"
      resources = ["*"]
      actions = ["kms:*"]

      principals {
        type = "AWS"
        identifiers = [data.aws_caller_identity.self.arn]
      }
    }
}

data "aws_kms_secrets" "creds" {
  secret {
    name = "db"
    payload = file("${path.module}/db-creds.yml.encrypted")
  }
}