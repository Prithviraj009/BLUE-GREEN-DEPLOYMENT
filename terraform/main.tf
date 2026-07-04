provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "bg_vpc"{
    cidr_block="10.0.0.0/16"

    tags={
        Name="bg-vpc"
    }
}

resource "aws_subnet" "bg_subnet"{
    count=2
    vpc_id=aws_vpc.bg_vpc.id
    cidr_block=cidrsubnet(aws_vpc.bg_vpc.cidr_block,8,count.index)
    availability_zone = data.aws_availability_zones.available.names[count.index]
    map_public_ip_on_launch = true

    tags = {
    Name = "bg-subnet-${count.index}"

    "kubernetes.io/role/elb" = "1"

    "kubernetes.io/cluster/example" = "shared"
    }

}

resource "aws_internet_gateway" "bg_igw" {
  vpc_id = aws_vpc.bg_vpc.id

  tags = {
    Name = "bg-igw"
  }
}

resource "aws_route_table" "bg_route_table" {
  vpc_id = aws_vpc.bg_vpc.id

 route {
  cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.bg_igw.id
}

  tags = {
    Name = "bg-route-table"
  }
}

resource "aws_route_table_association" "a" {
  count          = 2
  subnet_id      = aws_subnet.bg_subnet[count.index].id
  route_table_id = aws_route_table.bg_route_table.id
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "bg-eks-cluster"
  kubernetes_version = "1.34"


  endpoint_public_access = true


  enable_cluster_creator_admin_permissions = true

  vpc_id     = aws_vpc.bg_vpc.id
  subnet_ids = aws_subnet.bg_subnet[*].id

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }

  eks_managed_node_groups = {
  default = {
    instance_types = ["t3.medium"]
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }
}

}