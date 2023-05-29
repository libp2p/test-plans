terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.67.0"
    }
  }
}

variable "tags" {
  type = map(string)
  description = "Tags that the perf resources are tagged with"
}

variable "regions" {
  type = list(string)
  description = "Regions that the perf resources are created in"
}

resource "aws_iam_user" "perf" {
  name = "perf"
}

# TODO: Make the policy more restrictive; it needs to be able to create/destroy instances and key pairs
data "aws_iam_policy_document" "perf" {
  statement {
    actions   = ["ec2:*"]
    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_user_policy" "perf" {
  name = "perf"
  user = aws_iam_user.perf.name

  policy = data.aws_iam_policy_document.perf.json
}
