variable "user_names" {
  description = "The user name to use"
  type        = list(string)
}

variable "give_neo_cloudwatch_full_access" {
  description = "If true, neo gets full access to CloudWatch"
  type = bool
}