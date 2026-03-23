output "cluster_id" {
  value = aws_eks_cluster.smproject.id
}

output "node_group_id" {
  value = aws_eks_node_group.smproject.id
}

output "vpc_id" {
  value = aws_vpc.smproject_vpc.id
}

output "subnet_ids" {
  value = aws_subnet.smproject_subnet[*].id
}