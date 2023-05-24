variable "region" {
  type        = string
  description = "The AWS region to create resources in"
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
}

variable "bucket_name" {
  type        = string
  description = "The name of the S3 bucket to create"
}

provider "aws" {
  region = var.region

  tags = var.common_tags
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

resource "aws_s3_bucket" "perf" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_acl" "perf" {
  bucket = aws_s3_bucket.perf.id
  acl    = "private"
}

data "aws_iam_policy_document" "perf_assume_role" {
  statement {
    sid    = ""
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "perf_role" {
  name               = "perf-node-role"
  assume_role_policy = data.aws_iam_policy_document.perf_assume_role.json
}

resource "aws_iam_instance_profile" "perf_profile" {
  name = "perf-node-profile"
  role = aws_iam_role.perf_role.name
}

data "aws_iam_policy_document" "perf_bucket" {
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectAcl", "s3:PutObject", "s3:PutObjectAcl"]
    resources = ["${aws_s3_bucket.perf.arn}/*"]
    effect    = "Allow"
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.perf.arn}"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "perf_bucket" {
  name   = "perf-bucket-policy"
  role   = aws_iam_role.perf_role.name
  policy = data.aws_iam_policy_document.perf_bucket.json
}
