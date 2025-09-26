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
  iam_instance_profile = aws_iam_instance_profile.ec2_s3_write_profile.name
  #user_data = file("user_data.sh")
  user_data = <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install -y openjdk-21-jdk
    sudo apt install -y git

    sudo git clone ${var.repo_url} app
    cd app

    nohup sudo java -jar target/hellomvc-0.0.1-SNAPSHOT.jar --server.port=${var.my_app_port} > app.log 2>&1 &

    sudo apt update && sudo apt upgrade -y
    sudo apt install -y unzip curl

    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install

    # Create pre-shutdown script
    sudo tee /usr/local/bin/my-pre-shutdown.sh > /dev/null << 'EOT'
        #!/bin/bash
        aws s3 cp /var/log/cloud-init.log s3://my-bucket8302752601/$(hostname)-cloud-init.log
    EOT
    sudo chmod +x /usr/local/bin/my-pre-shutdown.sh

    # Create systemd service
    sudo tee /etc/systemd/system/my-upload-logs.service > /dev/null << 'EOT'
        [Unit]
        Description=Execute script before system shutdown
        DefaultDependencies=no
        Before=shutdown.target reboot.target halt.target

        [Service]
        Type=oneshot
        ExecStart=/bin/true
        ExecStop=/usr/local/bin/my-pre-shutdown.sh
        RemainAfterExit=yes

        [Install]
        WantedBy=shutdown.target reboot.target halt.target
    EOT

    sudo systemctl daemon-reload
    sudo systemctl enable my-upload-logs.service
    sudo systemctl start my-upload-logs.service
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


# iam read only
resource "aws_iam_role" "s3_read_role" {
  name = "S3ReadOnlyRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy_attachment" "attach_read_policy" {
  name       = "attach_read_policy"
  roles      = [aws_iam_role.s3_read_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}


#iam write,upload no read
resource "aws_iam_role" "s3_write_role" {
  name = "S3WriteOnlyRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "s3_write_policy" {
  name        = "S3WriteOnlyPolicy"
  description = "Allow creating buckets & uploading objects, deny read/list"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:CreateBucket", "s3:PutObject"]
        Resource = ["arn:aws:s3:::*", "arn:aws:s3:::*/*"]
      },
      {
        Effect = "Deny"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = ["arn:aws:s3:::*", "arn:aws:s3:::*/*"]
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "attach_write_policy" {
  name       = "attach_write_policy"
  roles      = [aws_iam_role.s3_write_role.name]
  policy_arn = aws_iam_policy.s3_write_policy.arn
}



#Create Private S3 Bucket (configurable)

resource "aws_s3_bucket" "logs_bucket" {
  bucket = "my-bucket8302752601"
  acl    = "private"
  force_destroy = true
}

#Add S3 Lifecycle Rule to Delete Logs after 7 Days

resource "aws_s3_bucket_lifecycle_configuration" "log_lifecycle" {
  bucket = aws_s3_bucket.logs_bucket.id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    filter {
      prefix = ""  # all objects
    }

    expiration {
      days = 7
    }
  }
}

# create aws_iam_instance_profile

resource "aws_iam_instance_profile" "ec2_s3_write_profile" {
  name = "EC2S3WriteProfile"
  role = aws_iam_role.s3_write_role.name
}

