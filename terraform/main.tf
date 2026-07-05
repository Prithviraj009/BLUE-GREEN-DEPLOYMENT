provider "aws" {
  region = "us-east-1"
}
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}


resource "aws_iam_policy" "aws_lb_controller" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = data.http.lb_controller_iam_policy.response_body
}

data "aws_iam_policy_document" "lb_controller_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [module.eks.oidc_provider_arn]
      type        = "Federated"
    }
  }
}
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.9.0"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.aws_lb_controller.metadata[0].name
  }

  set {
    name  = "region"
    value = "us-east-1"
  }

  set {
    name  = "vpcId"
    value = aws_vpc.bg_vpc.id
  }

  depends_on = [kubernetes_service_account.aws_lb_controller]
}

resource "kubernetes_service_account" "aws_lb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_lb_controller.arn
    }
  }

  depends_on = [module.eks]
}

resource "aws_iam_role" "aws_lb_controller" {
  name               = "aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume_role.json
}

resource "aws_iam_role_policy_attachment" "aws_lb_controller" {
  role       = aws_iam_role.aws_lb_controller.name
  policy_arn = aws_iam_policy.aws_lb_controller.arn
}


provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
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

    "kubernetes.io/cluster/bg-eks-cluster" = "shared"
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