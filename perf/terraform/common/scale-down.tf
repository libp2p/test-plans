data "archive_file" "scale_down" {
  type        = "zip"
  source_file = "${path.module}/files/scale_down.py"
  output_path = "${path.module}/files/scale_down.zip"
}

resource "aws_lambda_function" "scale_down" {
  filename         = data.archive_file.scale_down.output_path
  source_code_hash = data.archive_file.scale_down.output_base64sha256
  function_name    = "perf-scale-down"
  role             = aws_iam_role.scale_down.arn
  handler          = "scale_down.lambda_handler"
  runtime          = "python3.10"
  memory_size      = 128
  timeout          = 30
  tags             = var.common_tags

  environment {
    variables = {
      REGIONS         = ["us-east-1", "us-west-2"]
      TAGS            = merge(var.common_tags, { "Name" = "node" })
      MAX_AGE_MINUTES = 30
    }
  }
}

resource "aws_cloudwatch_log_group" "scale_down" {
  name              = "/aws/lambda/${aws_lambda_function.scale_down.function_name}"
  retention_in_days = 7
  tags              = var.common_tags
}

resource "aws_cloudwatch_event_rule" "scale_down" {
  name                = "perf-scale-down-rule"
  schedule_expression = "rate(1 hour)"
  tags                = var.common_tags
}

resource "aws_cloudwatch_event_target" "scale_down" {
  rule = aws_cloudwatch_event_rule.scale_down.name
  arn  = aws_lambda_function.scale_down.arn
}

resource "aws_lambda_permission" "scale_down" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scale_down.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scale_down.arn
}

resource "aws_iam_role" "scale_down" {
  name               = "perf-scale-down-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
  tags               = var.common_tags
}

data "aws_iam_policy_document" "scale_down" {
  statement {
    actions   = ["ec2:DescribeInstances", "ec2:DescribeTags"]
    resources = ["*"]
    effect    = "Allow"
  }

  statement {
    actions   = ["ec2:TerminateInstances"]
    resources = ["*"]
    effect    = "Allow"

    dynamic "condition" {
      for_each = aws_launch_template.perf.tag_specifications.tags

      content {
        test     = "StringEquals"
        variable = "ec2:ResourceTag/${condition.value.Key}"
        values   = [condition.value.Value]
      }
    }
  }
}

resource "aws_iam_role_policy" "scale_down" {
  name   = "perf-scale-down-lamda-policy"
  role   = aws_iam_role.scale_down.name
  policy = data.aws_iam_policy_document.scale_down.json
}

data "aws_iam_policy_document" "scale_down_logging" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.scale_down.arn}*"]
    effect    = "Allow"
  }

}

resource "aws_iam_role_policy" "scale_down_logging" {
  name   = "perf-lambda-logging"
  role   = aws_iam_role.scale_down.name
  policy = data.aws_iam_policy_document.scale_down_logging.json
}
