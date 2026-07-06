variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}
variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  default     = "10.0.1.0/24"
}
variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  default     = "10.0.2.0/24"
}
variable "instance_type" {
  description = "EC2 instance type"
  default     = "t3.micro"
}
variable "key_name" {
  description = "Name of the SSH key pair"
  default     = "mern-key"
}
variable "my_ip" {
  description = "Your public IP for SSH access"
  default     = "0.0.0.0/0"
}