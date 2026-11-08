terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
provider "aws" {
  region = "us-east-1"
}

# ========================================== 
# 1. NETWORKING: THE FOUNDATION 
# ========================================== 
resource "aws_vpc" "gds_vpc" {
  cidr_block = "10.0.0.0/16"
  tags       = { Name = "gds-mission-vpc" }
}
resource "aws_internet_gateway" "gds_igw" {
  vpc_id = aws_vpc.gds_vpc.id
  tags   = { Name = "gds-igw" }
}
# ========================================== 
# 2. SUBNETS: THE TIERED DEFENSE 
# ========================================== 
# Public Subnets (For ALB and NAT Gateway) 
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.gds_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "gds-public-1a" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.gds_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags                    = { Name = "gds-public-1b" }
}

# Private Subnets (For EKS Worker Nodes) 
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.gds_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "gds-private-1a" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.gds_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "gds-private-1b" }
}

# ========================================== 
# 3. SECURE OUTGOING TRAFFIC (NAT GATEWAY) 
# ========================================== 
# EIP for the NAT Gateway 
resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.gds_igw]
}
# NAT Gateway in Public Subnet (Represented by the Green line in your diagram) 
resource "aws_nat_gateway" "gds_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id
  tags          = { Name = "gds-nat-gateway" }
}


# ========================================== 
# 4. LOAD BALANCER: THE FRONT DOOR 
# ========================================== 
resource "aws_lb" "gds_alb" {
  name               = "gds-mission-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets = [aws_subnet.public_1.id,
  aws_subnet.public_2.id]
}
resource "aws_lb_target_group" "gds_tg" {
  name     = "gds-app-targets"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.gds_vpc.id
}
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.gds_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gds_tg.arn
  }
}
# ========================================== 
# 5. SECURITY GROUPS: THE PROTOCOLS 
# ========================================== 
resource "aws_security_group" "alb_sg" {
  name   = "gds-alb-sg"
  vpc_id = aws_vpc.gds_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Solid white lines from cloud icon 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}