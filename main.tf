#########################################################
# 0. Terraform & provider
#########################################################
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

#########################################################
# 1. IAM Roles (pré-existentes no AWS Academy)
#########################################################
data "aws_iam_role" "eks_cluster_role" { name = "labRole" }
data "aws_iam_role" "eks_node_role"    { name = "labRole" }

#########################################################
# 2. VPC pública minimalista (2 AZs)
#########################################################
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

locals {
  subnets = [
    { cidr = "10.0.1.0/24", az = "us-east-1a" },
    { cidr = "10.0.2.0/24", az = "us-east-1b" }
  ]
}

resource "aws_subnet" "public" {
  for_each                = { for s in local.subnets : s.az => s }
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "eks_cluster_sg" {
  name        = "eks-cluster-sg"
  description = "EKS cluster SG"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#########################################################
# 3. Cluster EKS
#########################################################
resource "aws_eks_cluster" "eks" {
  name     = "academy-cluster"
  version  = "1.29"
  role_arn = data.aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids         = values(aws_subnet.public)[*].id
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
  }

  lifecycle {
    ignore_changes = [bootstrap_self_managed_addons]
  }
}

#########################################################
# 4. Node Group
#########################################################
resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "academy-node-group"
  node_role_arn   = data.aws_iam_role.eks_node_role.arn
  subnet_ids      = values(aws_subnet.public)[*].id

  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 3
    max_size     = 3
    min_size     = 3
  }

  timeouts { create = "30m" }
}

#########################################################
# 5. Outputs
#########################################################
output "cluster_name"  { value = aws_eks_cluster.eks.name }
output "cluster_endpoint" { value = aws_eks_cluster.eks.endpoint }
output "cluster_certificate_authority_data" {
  value     = aws_eks_cluster.eks.certificate_authority[0].data
  sensitive = true
}
