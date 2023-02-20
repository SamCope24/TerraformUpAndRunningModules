resource "aws_db_instance" "example" {
  identifier_prefix   = "terraform-up-and-running"
  engine              = "mysql"
  allocated_storage   = 10
  instance_class      = "db.t2.micro"
  skip_final_snapshot = true
  db_name             = var.db_name
  username = local.db_creds.username
  password = local.db_creds.password
}

resource "aws_kms_key" "cmk" {
  policy = data.aws_iam_policy_document.cmk_admin_policy.json
}

resource "aws_kms_alias" "cmk" {
  name = "alias/kms-cmk-example/${var.db_name}"
  target_key_id = aws_kms_key.cmk.id
}