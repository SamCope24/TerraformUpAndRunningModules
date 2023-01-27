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

resource "aws_launch_configuration" "example" {
  image_id        = "ami-0fb653ca2d3203ac1"
  instance_type   = var.instance_type
  security_groups = [aws_security_group.instance.id] # links the EC2 instance to the security group

  # script that runs on startup and launches a websever, rendered via a template 
  user_data = templatefile("${path.module}/user-data.sh", { # see path.module, path.root, path.cwd
    server_port = var.server_port
    db_address  = data.terraform_remote_state.db.outputs.address
    db_port     = data.terraform_remote_state.db.outputs.port
  })

  # Required when using a launch configuration with an auto scaling group 
  lifecycle {
    create_before_destroy = true
  }
}

# creation of an auto scaling group that runs between 2 and 10 EC2 instances
resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier  = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size = var.min_size
  max_size = var.max_size

  tag {
    key                 = "Name"
    value               = var.cluster_name
    propagate_at_launch = true
  }
}

# aws securtiy group to allow incoming requests on port 8080 from any IP
resource "aws_security_group" "instance" {
  name = "${var.cluster_name}-instance"
}

resource "aws_security_group_rule" "instance_allow_http_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.instance.id
  
  from_port        = var.server_port
  to_port          = var.server_port
  protocol         = local.tcp_protocol
  cidr_blocks      = local.all_ips
  ipv6_cidr_blocks = local.all_ipv6_ips
}

# creates the application load balancer
resource "aws_alb" "example" {
  name               = var.cluster_name
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.alb.id]
}

# creates the ALB listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_alb.example.arn
  port              = local.http_port
  protocol          = "HTTP"

  # by default return a simple 404 page
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

# by default ALB does not allow any incoming/outgoing traffic so need a SG
resource "aws_security_group" "alb" {
  name = "${var.cluster_name}-alb"
}

# Allow inbound HTTP requests
resource "aws_security_group_rule" "alb_allow_http_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.alb.id
  
  from_port        = local.http_port
  to_port          = local.http_port
  protocol         = local.tcp_protocol
  cidr_blocks      = local.all_ips
  ipv6_cidr_blocks = local.all_ipv6_ips
}

# Allow inbound HTTP requests
resource "aws_security_group_rule" "alb_allow_all_outbound" {
  type = "egress"
  security_group_id = aws_security_group.alb.id
  
  from_port        = local.any_port
  to_port          = local.any_port
  protocol         = local.any_protocol
  cidr_blocks      = local.all_ips
  ipv6_cidr_blocks = local.all_ipv6_ips
}

# create a target group for our ASG
resource "aws_lb_target_group" "asg" {
  name     = var.cluster_name
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  # health checks our EC2 instances periodically and only considers an instance
  # as healthy if we get a 200 OK response as defined by our matcher
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# creates the ALB listener rules which send requests that match any path
# to the target group that contains our ASG
resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

# read outputs from the database's state file 
# all od the database's output variables are stored in the state file
data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.db_remote_state_bucket
    key    = var.db_remote_state_key
    region = "us-east-2"
  }
}