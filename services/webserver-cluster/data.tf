# acts as a datasource for the default aws vpc
data "aws_vpc" "default" {
  default = true
}

# used to pull subnet data from the default vpc
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# read outputs from the database's state file 
# all of the database's output variables are stored in the state file
data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.db_remote_state_bucket
    key    = var.db_remote_state_key
    region = "us-east-2"
  }
}