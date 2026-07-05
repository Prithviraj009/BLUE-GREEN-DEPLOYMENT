data "aws_availability_zones" "available" {
  state = "available"
}
data "http" "lb_controller_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.9.0/docs/install/iam_policy.json"
}