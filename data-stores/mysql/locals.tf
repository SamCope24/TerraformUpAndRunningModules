locals {
  db_creds = yamldecode(data.aws_kms_secrets.creds.plaintext["db"])
}