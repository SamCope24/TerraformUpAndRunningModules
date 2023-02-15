
resource "aws_launch_configuration" "example" {
  image_id        = var.ami
  instance_type   = var.instance_type
  security_groups = [aws_security_group.instance.id] # links the EC2 instance to the security group

  # script that runs on startup and launches a websever, rendered via a template 
  user_data = templatefile("${path.module}/user-data.sh", { # see path.module, path.root, path.cwd
    server_port = var.server_port
    db_address  = data.terraform_remote_state.db.outputs.address
    db_port     = data.terraform_remote_state.db.outputs.port
    server_text = var.server_text
  })

  # Required when using a launch configuration with an auto scaling group 
  lifecycle {
    create_before_destroy = true
  }
}

# creation of an auto scaling group that runs between 2 and 10 EC2 instances
resource "aws_autoscaling_group" "example" {
  # explicitly depend on the launch configurations name so each time it's
  # replaced, this ASG is also replaced
  name = "${var.cluster_name}-${aws_launch_configuration.example.name}"

  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier  = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size = var.min_size
  max_size = var.max_size

  # use instance referesh to roll out changes to the ASG
  # allows AWS to handle the changes meaning below approach is not required
  instance_refresh {
    strategy = "Rolling"
    
    preferences {
      min_healthy_percentage = 50
    }
  }

  # # wait for at least this many instances to pass health checks before
  # # considering the ASG deployment complete
  # min_elb_capacity = var.min_size

  # # when replacing this ASG, create the replacement first, and only delete
  # # the original after
  # lifecycle {
  #   create_before_destroy = true
  # }

  tag {
    key                 = "Name"
    value               = var.cluster_name
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = {
      for key, value in var.custom_tags:
        key => upper(value)
        if key != "Name"
    }

    content {
      key = tag.key
      value = tag.value
      propagate_at_launch = true
    }
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

# scheduled action to increase ASG capacity in core business hours
resource "aws_autoscaling_schedule" "scale_out_during_business_hours" {
  count = var.enable_autoscaling ? 1 : 0
  
  scheduled_action_name = "${var.cluster_name}-scale-out-during-business-hours"
  min_size = 2
  max_size = 10
  desired_capacity = 10
  recurrence = "0 9 * * *" # cron syntax - 9am every day

  autoscaling_group_name = aws_autoscaling_group.example.name
}

# scheduled action to decrease ASG capacity outside of core business hours
resource "aws_autoscaling_schedule" "scale_in_at_night" {
  count = var.enable_autoscaling ? 1 : 0

  scheduled_action_name = "${var.cluster_name}-scale-in-at-night"
  min_size = 2
  max_size = 10
  desired_capacity = 2
  recurrence = "0 17 * * *" # cron syntax - 5pm every day

  autoscaling_group_name = aws_autoscaling_group.example.name
}