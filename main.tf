terraform {
  backend "s3" {
    bucket         = "carlyle-terraform-state-unique-id" # Neenga create panna bucket name
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    #dynamodb_table = "terraform-lock"        # Optional: State lock panna
  }
}

# 1. AWS Provider Configuration
provider "aws" {
  region = "us-east-1" 
}

# 2. VPC (Private Network for Carlyle App)
resource "aws_vpc" "carlyle_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "Carlyle-VPC" }
}

# 3. Internet Gateway (To connect to the internet)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.carlyle_vpc.id
  tags   = { Name = "Carlyle-IGW" }
}

# 4. Public Subnet (Where our server will live)
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.carlyle_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags                    = { Name = "Carlyle-Public-Subnet" }
}

# 5. Route Table (The GPS for your network)
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.carlyle_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# 6. Associate Route Table with Subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# 7. Security Group for EC2 (Firewall)
resource "aws_security_group" "app_sg" {
  name        = "carlyle-app-sg"
  vpc_id      = aws_vpc.carlyle_vpc.id

  # Allow HTTP (Port 80) for the Web App
 ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH (Port 22) for you to login
  ingress {
    from_port   = 22
    to_port     = 22
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

# 8. EC2 Instance (Docker Setup)
resource "aws_instance" "carlyle_server" {
  ami                    = "ami-0c7217cdde317cfec" 
  instance_type          = "t2.micro"             
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y docker.io
              sudo systemctl start docker
              sudo systemctl enable docker
              # Carlyle App sample container
              sudo docker run -d -p 8080:80 --name carlyle-app-v2 nginxdemos/hello
              EOF

  tags = {
    Name = "Carlyle-App-Server"
  }
}