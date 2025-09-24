provider "aws" {
  region = var.aws_region
  access_key = var.access_key
  secret_key = var.secret_key
  }
resource "aws_instance" "ubuntu" {
  ami           = var.ami_id   
  instance_type = var.instance_type
  key_name = "ec2_key_1"
  depends_on    = [aws_key_pair.my_key] 
  security_groups = [aws_security_group.my_app_sg.name]
  user_data = <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install -y openjdk-21-jdk
    sudo apt install -y git
    sudo git clone ${var.repo_url} app
    cd app
    nohup sudo java -jar target/hellomvc-0.0.1-SNAPSHOT.jar --server.port=${var.my_app_port} > app.log 2>&1 &
  EOF


  tags = {
    ENV = "${var.stage}"
  }
  
}


resource "aws_security_group" "my_app_sg" {
  name        = "sg"
  description = "Allow SSH and HTTP"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = var.my_app_port
    to_port     = var.my_app_port
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

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content  = tls_private_key.example.private_key_pem
  filename = "private_key/ec2_key_1.pem"
  
}


resource "aws_key_pair" "my_key" {
  key_name = "ec2_key_1"
  public_key = tls_private_key.example.public_key_openssh  # Path to your existing public key file
}

