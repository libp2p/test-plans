variable "region" {
  type        = string
  description = "The AWS region to create resources in"
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.common_tags
  }
}

resource "aws_iam_user" "perf" {
  name = "perf"
}

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
