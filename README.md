# EKS-Terraform-Template

[![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Amazon EKS](https://img.shields.io/badge/Amazon%20EKS-%2323412B?style=for-the-badge&logo=amazon-eks&logoColor=white)](https://aws.amazon.com/eks/)

This Terraform configuration deploys a fully functional Amazon EKS (Elastic Kubernetes Service) cluster named `smproject-cluster` in the `eu-west-1` region. It includes:

- VPC (`smproject-vpc`) with CIDR `10.0.0.0/16`
- 2 public subnets (`smproject-subnet-0`, `smproject-subnet-1`) across `eu-west-1a`/`eu-west-1b`
- Internet Gateway and public route table
- EKS cluster with EBS CSI driver addon
- Managed node group (`smproject-node-group`) with 3 `c7i-flex.large` instances
- Required IAM roles and security groups (open for demo; restrict in production)
- SSH access via key pair (default: `Saurav-Mishra`)

## Prerequisites

1. AWS account with admin privileges
2. [AWS CLI](https://aws.amazon.com/cli/) configured (`aws configure`)
3. [Terraform](https://www.terraform.io/downloads.html) >= 1.0 installed
4. SSH key pair `Saurav-Mishra` in EC2 console (or override via `TF_VAR_ssh_key_name`)
5. Permissions for EKS, EC2, IAM, VPC

**Note:** Uses AWS managed policies; cluster role uses `AmazonEKSClusterPolicy`, nodes use worker policies + CNI/ECR/EBS.

## Quick Start

From the `terraform/EKS-Terraform/` directory:

```bash
terraform init
terraform plan
terraform apply
```

Enter `yes` to deploy. Deployment takes 10-15 minutes.

Connect to cluster:

```bash
aws eks update-kubeconfig --region eu-west-1 --name smproject-cluster
kubectl get nodes
```

## Configuration

Set via `variables.tf` or environment vars (`TF_VAR_ssh_key_name`):

| Variable       | Description                 | Default         |
| -------------- | --------------------------- | --------------- |
| `ssh_key_name` | SSH key pair name for nodes | `Saurav-Mishra` |

## Outputs

After `apply`:

```bash
terraform output
```

| Name            | Description                          |
| --------------- | ------------------------------------ |
| `cluster_id`    | EKS cluster ID (`smproject-cluster`) |
| `node_group_id` | Node group ID                        |
| `vpc_id`        | VPC ID                               |
| `subnet_ids`    | List of subnet IDs                   |

## Architecture

```
Internet Gateway
       |
VPC (10.0.0.0/16)
├── Subnet eu-west-1a (10.0.64.0/18)
├── Subnet eu-west-1b (10.0.128.0/18)
    |
EKS Cluster (smproject-cluster)
└── Node Group (3x c7i-flex.large)
```

## Teardown

```bash
terraform destroy
```

## Troubleshooting

- **Init fails**: Check AWS credentials.
- **Apply hangs**: Node provisioning can take time; check EC2 console.
- **Nodes not ready**: Verify security groups, IAM roles.
- Update Terraform providers: `terraform init -upgrade`.

## Next Steps

- Add Kubernetes manifests/Helm charts
- Enable private subnets
- Integrate with EKS addons (Ingress, etc.)
- CI/CD with Terraform Cloud/Atlantis

For production: Tighten SGs, use private endpoints, IRSA, etc.
