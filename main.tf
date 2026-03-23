provider "aws" {
  region = "eu-west-1"
}

# ---------------- VPC ----------------
resource "aws_vpc" "smproject_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "smproject-vpc"
  }
}

resource "aws_subnet" "smproject_subnet" {
  count = 2
  vpc_id                  = aws_vpc.smproject_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.smproject_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["eu-west-1a", "eu-west-1b"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "smproject-subnet-${count.index}"
  }
}

resource "aws_internet_gateway" "smproject_igw" {
  vpc_id = aws_vpc.smproject_vpc.id

  tags = {
    Name = "smproject-igw"
  }
}

resource "aws_route_table" "smproject_route_table" {
  vpc_id = aws_vpc.smproject_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.smproject_igw.id
  }

  tags = {
    Name = "smproject-route-table"
  }
}

resource "aws_route_table_association" "smproject_association" {
  count          = 2
  subnet_id      = aws_subnet.smproject_subnet[count.index].id
  route_table_id = aws_route_table.smproject_route_table.id
}

# ---------------- SECURITY GROUPS ----------------
resource "aws_security_group" "smproject_cluster_sg" {
  vpc_id = aws_vpc.smproject_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "smproject-cluster-sg"
  }
}

resource "aws_security_group" "smproject_node_sg" {
  vpc_id = aws_vpc.smproject_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "smproject-node-sg"
  }
}

# ---------------- IAM ROLES ----------------
resource "aws_iam_role" "smproject_cluster_role" {
  name = "smproject-cluster-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "smproject_cluster_role_policy" {
  role       = aws_iam_role.smproject_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "smproject_node_group_role" {
  name = "smproject-node-group-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "smproject_node_group_role_policy" {
  role       = aws_iam_role.smproject_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "smproject_node_group_cni_policy" {
  role       = aws_iam_role.smproject_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "smproject_node_group_registry_policy" {
  role       = aws_iam_role.smproject_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# (kept as you asked, but not used by addon anymore)
resource "aws_iam_role_policy_attachment" "smproject_node_group_ebs_policy" {
  role       = aws_iam_role.smproject_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ---------------- EKS CLUSTER ----------------
resource "aws_eks_cluster" "smproject" {
  name     = "smproject-cluster"
  role_arn = aws_iam_role.smproject_cluster_role.arn

  vpc_config {
    subnet_ids         = aws_subnet.smproject_subnet[*].id
    security_group_ids = [aws_security_group.smproject_cluster_sg.id]
  }
}

# ---------------- NODE GROUP ----------------
resource "aws_eks_node_group" "smproject" {
  cluster_name    = aws_eks_cluster.smproject.name
  node_group_name = "smproject-node-group"
  node_role_arn   = aws_iam_role.smproject_node_group_role.arn
  subnet_ids      = aws_subnet.smproject_subnet[*].id

  scaling_config {
    desired_size = 3
    max_size     = 3
    min_size     = 3
  }

  instance_types = ["c7i-flex.large"]

  remote_access {
    ec2_ssh_key = var.ssh_key_name
    source_security_group_ids = [aws_security_group.smproject_node_sg.id]
  }
}

# ---------------- IRSA (FIX) ----------------
data "aws_eks_cluster" "smproject" {
  name = aws_eks_cluster.smproject.name
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.smproject.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da0ecd7d5f6"]
}

resource "aws_iam_role" "ebs_csi_driver_role" {
  name = "AmazonEKS_EBS_CSI_DriverRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.smproject.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy" {
  role       = aws_iam_role.ebs_csi_driver_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ---------------- EBS CSI ADDON (FIXED) ----------------
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.smproject.name
  addon_name   = "aws-ebs-csi-driver"

  service_account_role_arn = aws_iam_role.ebs_csi_driver_role.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.smproject
  ]
}
