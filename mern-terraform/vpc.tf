# VPC
resource "aws_vpc" "mern_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "mern-vpc"
  }
}
# Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.mern_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "mern-public-subnet"
  }
}
# Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.mern_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.aws_region}a"
  tags = {
    Name = "mern-private-subnet"
  }
}
# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.mern_vpc.id
  tags = {
    Name = "mern-igw"
  }
}
# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}
# NAT Gateway (in public subnet)
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
  tags = {
    Name = "mern-nat-gw"
  }
}
# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.mern_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "mern-public-rt"
  }
}
# Associate Public Route Table with Public Subnet
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}
# Private Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.mern_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  tags = {
    Name = "mern-private-rt"
  }
}
# Associate Private Route Table with Private Subnet
resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}