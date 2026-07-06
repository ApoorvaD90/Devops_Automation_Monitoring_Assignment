# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "mern-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}
# Attach SSM Policy to Role
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
# Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "mern-ec2-profile"
  role = aws_iam_role.ec2_role.name
}