terraform {
  required_version = "> 0.7.0"
}

provider "aws" {
  version = "~> 1.16"
  region  = "${var.aws_region}"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

#create event log group
resource "aws_cloudwatch_log_group" "vpc-log-group" {
  name              = "event-log-group"
  retention_in_days = 90
  tags              = {}
}

#*********************create s3 bucket*********************

resource "aws_s3_bucket" "vpc-log-trail-bucket" {
  bucket        = "vpc-log-trail-bucket"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "vpc-log-trail-bucket-policy" {
  bucket = "${aws_s3_bucket.vpc-log-trail-bucket.id}"
  policy = "${data.aws_iam_policy_document.vpc-log-trail-bucket-policy-doc.json}"
}

data "aws_iam_policy_document" "vpc-log-trail-bucket-policy-doc" {
  statement {
    effect  = "Allow"
    sid     = "AWSCloudTrailAclCheck20150319"
    actions = ["s3:GetBucketAcl"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.vpc-log-trail-bucket.arn}"]
  }

  statement {
    effect  = "Allow"
    sid     = "AWSCloudTrailWrite20150319"
    actions = ["s3:PutObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    resources = ["${aws_s3_bucket.vpc-log-trail-bucket.arn}/*"]
  }
}

#********************* create trail *********************
data "aws_iam_policy_document" "vpc-log-trail-cloudwatch-policy-doc" {
  statement {
    effect = "Allow"
    sid    = "AWSCloudTrailCreateLogStream20141101"

    actions = [
      "logs:CreateLogStream",
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${aws_cloudwatch_log_group.vpc-log-group.id}:log-stream:${data.aws_caller_identity.current.account_id}_CloudTrail_${data.aws_region.current.name}*",
    ]
  }

  statement {
    effect = "Allow"
    sid    = "AWSCloudTrailPutLogEvents20141101"

    actions = [
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${aws_cloudwatch_log_group.vpc-log-group.id}:log-stream:${data.aws_caller_identity.current.account_id}_CloudTrail_${data.aws_region.current.name}*",
    ]
  }
}

resource "aws_iam_role" "vpc-log-trail-cloudwatch-role" {
  name               = "CloudTrail_CloudWatchLogs_Role"
  assume_role_policy = "${file("vpc_cloudtrail_assume_role_policy.json")}"
}

resource "aws_iam_policy" "vpc-log-trail-cloudwatch-policy" {
  name   = "vpc-log-trail-cloudwatch-policy"
  policy = "${data.aws_iam_policy_document.vpc-log-trail-cloudwatch-policy-doc.json}"
}

resource "aws_iam_policy_attachment" "vpc-log-trail-cloudwatch-role-attach-policy" {
  name       = "CloudTrail_CloudWatchLogs_Role_Attach_Policy"
  roles      = ["${aws_iam_role.vpc-log-trail-cloudwatch-role.name}"]
  policy_arn = "${aws_iam_policy.vpc-log-trail-cloudwatch-policy.arn}"
}

resource "aws_cloudtrail" "vpc-log-trail" {
  name           = "vpc-log-trail"
  s3_key_prefix  = ""
  s3_bucket_name = "${aws_s3_bucket.vpc-log-trail-bucket.id}"

  cloud_watch_logs_role_arn     = "${aws_iam_role.vpc-log-trail-cloudwatch-role.arn}"
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.vpc-log-group.arn}"
  include_global_service_events = false

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = ["aws_s3_bucket_policy.vpc-log-trail-bucket-policy"]
}

#********************* create lambda *********************

resource "aws_iam_role" "iam-for-lambda-bridge-role" {
  name               = "iam-for-lambda-bridge-role"
  assume_role_policy = "${file("vpc_lambda_assume_role_policy.json")}"
}

resource "aws_iam_policy" "iam-for-lambda-bridge-policy" {
  name   = "iam-for-lambda-bridge-policy"
  policy = "${file("vpc_lambda_bridge_policy.json")}"
}

resource "aws_iam_policy_attachment" "iam-for-lambda-bridge-attach-policy" {
  name       = "Lambda_CloudWatchLogs_Role_Attach_Policy"
  roles      = ["${aws_iam_role.iam-for-lambda-bridge-role.name}"]
  policy_arn = "${aws_iam_policy.iam-for-lambda-bridge-policy.arn}"
}

resource "aws_lambda_function" "lambda_bridge" {
  filename         = "bridge.zip"
  function_name    = "lambda_bridge_function"
  role             = "${aws_iam_role.iam-for-lambda-bridge-role.arn}"
  handler          = "bridge.handler"
  source_code_hash = "${base64sha256(file("bridge.zip"))}"
  runtime          = "python3.6"

  environment {
    variables = {
      EMAIL_FROM = ""
      EMAIL_TO   = ""
    }
  }
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda_bridge.arn}"
  principal     = "logs.${data.aws_region.current.name}.amazonaws.com"

  #source_arn     = "${aws_s3_bucket.vpc-log-trail-bucket.arn}"
}

resource "aws_cloudwatch_log_subscription_filter" "lambda_bridge_logfilter" {
  name            = "lambda_bridge_logfilter"
  filter_pattern  = "{  $.eventName = RunInstances ||  $.eventName = TerminateInstances }"
  log_group_name  = "${aws_cloudwatch_log_group.vpc-log-group.name}"
  destination_arn = "${aws_lambda_function.lambda_bridge.arn}"
}
