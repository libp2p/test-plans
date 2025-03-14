data "archive_file" "cleanup" {
  type        = "zip"
  source_file = "${path.module}/files/cleanup.py"
  output_path = "${path.module}/files/cleanup.zip"
}

resource "aws_lambda_function" "cleanup" {
  filename         = data.archive_file.cleanup.output_path
  source_code_hash = data.archive_file.cleanup.output_base64sha256
  function_name    = "perf-cleanup"
  role             = aws_iam_role.cleanup.arn
  handler          = "cleanup.lambda_handler"
  runtime          = "python3.9"
  memory_size      = 128
  timeout          = 30

  environment {
    variables = {
      REGIONS         = jsonencode(var.regions)
      TAGS            = jsonencode(var.tags)
      MAX_AGE_MINUTES = 540
    }
  }
}

resource "aws_cloudwatch_log_group" "cleanup" {
  name              = "/aws/lambda/${aws_lambda_function.cleanup.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_event_rule" "cleanup" {
  name                = "perf-cleanup-rule"
  schedule_expression = "cron(37 * * * ? *)" # 00:37, 01:37, 02:37, ..., 23:37
}

resource "aws_cloudwatch_event_target" "cleanup" {
  rule = aws_cloudwatch_event_rule.cleanup.name
  arn  = aws_lambda_function.cleanup.arn
}

resource "aws_lambda_permission" "cleanup" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cleanup.arn
}

data "aws_iam_policy_document" "cleanup_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cleanup" {
  name               = "perf-cleanup-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.cleanup_assume_role.json
}

data "aws_iam_policy_document" "cleanup" {
  statement {
    actions   = ["ec2:DescribeInstances", "ec2:DescribeTags", "ec2:DescribeKeyPairs"]
    resources = ["*"]
    effect    = "Allow"
  }

  statement {
    actions   = ["ec2:TerminateInstances", "ec2:DeleteKeyPair"]
    resources = ["*"]
    effect    = "Allow"

    dynamic "condition" {
      for_each = var.tags

      content {
        test     = "StringEquals"
        variable = "ec2:ResourceTag/${condition.key}"
        values   = [condition.value]
      }
    }
  }
}

resource "aws_iam_role_policy" "cleanup" {
  name   = "perf-cleanup-lamda-policy"
  role   = aws_iam_role.cleanup.name
  policy = data.aws_iam_policy_document.cleanup.json
}

data "aws_iam_policy_document" "cleanup_logging" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.cleanup.arn}*"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "cleanup_logging" {
  name   = "perf-lambda-logging"
  role   = aws_iam_role.cleanup.name
  policy = data.aws_iam_policy_document.cleanup_logging.json
}
