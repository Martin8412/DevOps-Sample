terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
}

provider "aws" {
  profile = "default"
  region  = "eu-west-1"
}

resource "aws_ecr_repository" "wordpress" {
  name                 = "wordpress"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "main1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"

  availability_zone = "eu-west-1a"

  map_public_ip_on_launch = true

  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "main2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"

  availability_zone = "eu-west-1b"

  map_public_ip_on_launch = true

  tags = {
    Name = "main"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "main"
  }
}

resource "aws_main_route_table_association" "main" {
  vpc_id         = aws_vpc.main.id
  route_table_id = aws_route_table.main.id
}

resource "aws_security_group" "lb_allow_http_and_https" {
  name        = "lb_allow_http_and_https"
  description = "Allows HTTP and HTTPS traffic to pass the load balancer"

  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP from world"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from world"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_security_group" "allow_http_from_lb" {
  name        = "allow_http_from_lb"
  description = "Allows HTTP from the load balancer to the ECS node"

  vpc_id = aws_vpc.main.id

  ingress {
    description     = "HTTP from loadbalancer"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_allow_http_and_https.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "allow_ecs_to_mysql" {
  name        = "allow_ecs_to_mysql"
  description = "Allows ECS to MySQL"

  vpc_id = aws_vpc.main.id

  ingress {
    description = "ECS to MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "main"
  subnet_ids = [aws_subnet.main1.id, aws_subnet.main2.id]

  tags = {
    Name = "Wordpress DB subnet group"
  }
}

resource "aws_db_instance" "wordpress" {
  allocated_storage          = 10
  engine                     = "mysql"
  engine_version             = "5.7"
  instance_class             = "db.t3.micro"
  name                       = "wordpress"
  username                   = "wordpress"
  password                   = "wordpress"
  parameter_group_name       = "default.mysql5.7"
  skip_final_snapshot        = true
  auto_minor_version_upgrade = true
  db_subnet_group_name       = aws_db_subnet_group.wordpress.name
  vpc_security_group_ids     = [aws_security_group.allow_ecs_to_mysql.id]
}

resource "aws_ecs_cluster" "wordpress" {
  name = "wordpress"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "wordpress" {
  family                = "wordpress"
  container_definitions = <<EOF
  [
    {
      "name": "wordpress",
      "image": "381501831417.dkr.ecr.eu-west-1.amazonaws.com/wordpress:latest",
      "memory": 512,
      "requiresCompatibilities": "FARGATE",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 80
        }
      ],
      "environment": [
        {"name": "DB_HOST", "value": "${aws_db_instance.wordpress.address}"},
        {"name": "DB_NAME", "value": "${aws_db_instance.wordpress.name}"},
        {"name": "DB_USER", "value": "${aws_db_instance.wordpress.username}"},
        {"name": "DB_PASSWORD", "value": "${aws_db_instance.wordpress.password}"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "awslogs-wordpress",
            "awslogs-region": "eu-west-1",
            "awslogs-stream-prefix": "awslogs-wordpress"
        }
      }
    }
  ]
  EOF
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn = "arn:aws:iam::381501831417:role/ecsTaskExecutionRole"
}

//resource "aws_iam_service_linked_role" "ecs" {
//  aws_service_name = "ecs.amazonaws.com"
//}

resource "aws_lb_target_group" "wordpress" {
  name     = "wordpress"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "ip"
  depends_on = [ aws_lb.wordpress ]
}

resource "aws_lb" "wordpress" {
  name               = "wordpress-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_allow_http_and_https.id]
  subnets            = [aws_subnet.main1.id, aws_subnet.main2.id]

  enable_deletion_protection = false
}

resource "aws_acm_certificate" "wordpress" {
  domain_name       = "wp.martin8412.dk"
  validation_method = "DNS"
}

resource "aws_route53_zone" "wordpress" {
  name         = "wp.martin8412.dk"
}

resource "aws_route53_record" "wordpress" {
  for_each = {
    for dvo in aws_acm_certificate.wordpress.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.wordpress.zone_id
}

//resource "aws_acm_certificate_validation" "wordpress" {
//  certificate_arn         = aws_acm_certificate.wordpress.arn
//  validation_record_fqdns = [for record in aws_route53_record.wordpress : record.fqdn]
//}

/*
resource "aws_lb_listener" "wordpress_tls" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.wordpress.certificate_arn


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}
*/

resource "aws_lb_listener" "wordpress" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_ecs_service" "wordpress" {
  name            = "wordpress"
  cluster         = aws_ecs_cluster.wordpress.id
  task_definition = aws_ecs_task_definition.wordpress.arn
  desired_count   = 1
  launch_type = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.wordpress.arn
    container_name   = "wordpress"
    container_port   = 80
  }

  network_configuration {
    subnets = [aws_subnet.main1.id, aws_subnet.main2.id]
    security_groups = [ aws_security_group.allow_http_from_lb.id ]
    assign_public_ip = true
  }
}