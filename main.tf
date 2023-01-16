terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>3.0"
    }
  }

  required_version = ">=0.12.31"
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "sec-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

# Define the security group for the Windows server listening on port 80
resource "aws_security_group" "aws-sg" {
  name        = "second_sg"
  description = "Allow incoming connections"
  vpc_id      = "vpc-06c32d2a6eb38ff38"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow incoming HTTP connections"
  }
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow incoming RDP connections"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "second_sg"
  }
}

# Get latest Windows Server 2019 AMI
data "aws_ami" "windows-2019" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base*"]
  }
}

resource "aws_instance" "windows-server"{
  instance_type = "t2.micro"
  ami = data.aws_ami.windows-2019.id
  vpc_security_group_ids = ["sg-06e5ead5fd3a48f76"]
  subnet_id = "subnet-06cfdb46817604330" 
  user_data  = file("sample_website2.sh")
  tags = {
    Name = "windows_server2"
  }
}

# Get Linux AMI
data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

resource "aws_instance" "linux-server"{
  instance_type = "t2.micro"
  ami = data.aws_ami.amazon-linux-2.id
  vpc_security_group_ids = ["sg-06e5ead5fd3a48f76"]
  subnet_id = "subnet-0dc20436e46416488" 
  user_data  = file("sample_website.sh")
  tags = {
    Name = "linux_server2"
  }
}

# Aplication Load Balancer Configuration listening on port 80
resource "aws_lb_target_group" "front" {
  name     = "application-front2"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "vpc-06c32d2a6eb38ff38"
  health_check {
    enabled = true
    healthy_threshold = 3
    interval = 10
    matcher = 200
    path = "/"
    port = "traffic-port"
    protocol = "HTTP"
    timeout = 3
    unhealthy_threshold = 2
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment
resource "aws_lb_target_group_attachment" "attach-app1" {
  target_group_arn = aws_lb_target_group.front.arn
  target_id        = "i-09e5d3f3c4ef35b6d"
  port             = 80
}
resource "aws_lb_target_group_attachment" "attach-app2" {
  target_group_arn = aws_lb_target_group.front.arn
  target_id        = "i-083b81f95bb0b4b0c"
  port             = 80
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.front.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.front.arn
  }
}
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
resource "aws_lb" "front" {
  name               = "front2"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-06e5ead5fd3a48f76"]
  subnets            = ["subnet-06cfdb46817604330","subnet-0dc20436e46416488"]

  enable_deletion_protection = false

  tags = {
    Environment = "front2"
  }
}
