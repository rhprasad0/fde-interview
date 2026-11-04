# The OPM watcher: a daily rule runs fetch.py, which lands each new current OPM FWD file in S3 and invokes load.py, which
# records it in ops.opm_files on the RDS instance (DECISIONS.md, OPM watcher). Two functions because the VPC has no NAT:
# fetch needs the internet and runs outside it; load needs RDS and runs inside it. About $0.10 a month.
#
#   uv pip install --target ../pipeline/build/loader pg8000 && cp ../pipeline/load.py ../pipeline/build/loader/
#   terraform apply
#   psql -v pipeline_password="$PIPELINE_PGPASSWORD" -f ../sql/05_pipeline.pg.sql   # PIPELINE_* from pg_env
#   aws lambda invoke --function-name workforce-opm-fetch /dev/stdout                 # or wait for 06:00 UTC

variable "opm_since" {
  type        = string
  default     = "202608" # the last month the agent's tables hold, so the first run lands August and then waits for September
  description = "First OPM data month (YYYYMM) to land"
}

resource "random_password" "pipeline" {
  length  = 32
  special = false
}

resource "aws_s3_bucket" "landing" {
  bucket_prefix = "workforce-opm-landing-"
  force_destroy = true # destroy when done, like the instance
}

data "archive_file" "fetch" {
  type        = "zip"
  source_file = "${path.module}/../pipeline/fetch.py"
  output_path = "${path.module}/../pipeline/build/fetch.zip"
}

data "archive_file" "load" {
  type        = "zip"
  source_dir  = "${path.module}/../pipeline/build/loader" # load.py plus pg8000, from the pip line above
  output_path = "${path.module}/../pipeline/build/load.zip"
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# --- load: inside the VPC, writes as role pipeline ---

resource "aws_security_group" "pipeline" {
  name   = "workforce-pipeline"
  vpc_id = data.aws_vpc.default.id
  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
}

resource "aws_iam_role" "load" {
  name               = "workforce-opm-load"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "load" {
  role       = aws_iam_role.load.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_cloudwatch_log_group" "load" {
  name              = "/aws/lambda/workforce-opm-load"
  retention_in_days = 14
}

resource "aws_lambda_function" "load" {
  function_name    = "workforce-opm-load"
  role             = aws_iam_role.load.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "load.handler"
  filename         = data.archive_file.load.output_path
  source_code_hash = data.archive_file.load.output_base64sha256
  timeout          = 30
  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.pipeline.id]
  }
  environment {
    # shortcut: password as an encrypted env var, as on the app's task; Secrets Manager if the account outlives the demo.
    variables = {
      PGHOST     = aws_db_instance.workforce.address
      PGDATABASE = "workforce"
      PGUSER     = "pipeline"
      PGPASSWORD = random_password.pipeline.result
    }
  }
  depends_on = [aws_iam_role_policy_attachment.load, aws_cloudwatch_log_group.load]
}

# --- fetch: outside the VPC, internet to OPM and S3 ---

resource "aws_iam_role" "fetch" {
  name               = "workforce-opm-fetch"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "fetch" {
  role       = aws_iam_role.fetch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "fetch" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.landing.arn}/*"]
  }
  statement {
    actions   = ["s3:ListBucket"] # so a missing key is a 404, not a 403
    resources = [aws_s3_bucket.landing.arn]
  }
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.load.arn]
  }
}

resource "aws_iam_role_policy" "fetch" {
  role   = aws_iam_role.fetch.id
  policy = data.aws_iam_policy_document.fetch.json
}

resource "aws_cloudwatch_log_group" "fetch" {
  name              = "/aws/lambda/workforce-opm-fetch"
  retention_in_days = 14
}

resource "aws_lambda_function" "fetch" {
  function_name    = "workforce-opm-fetch"
  role             = aws_iam_role.fetch.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "fetch.handler"
  filename         = data.archive_file.fetch.output_path
  source_code_hash = data.archive_file.fetch.output_base64sha256
  timeout          = 900 # an employment file is about 57 MB
  memory_size      = 512
  environment {
    variables = {
      BUCKET = aws_s3_bucket.landing.id
      LOADER = aws_lambda_function.load.function_name
      SINCE  = var.opm_since
    }
  }
  depends_on = [aws_iam_role_policy_attachment.fetch, aws_cloudwatch_log_group.fetch]
}

# --- schedule: OPM posted August between 00:00 and 04:00 UTC, so look after that ---

resource "aws_cloudwatch_event_rule" "daily" {
  name                = "workforce-opm-daily"
  schedule_expression = "cron(0 6 * * ? *)"
}

resource "aws_cloudwatch_event_target" "fetch" {
  rule = aws_cloudwatch_event_rule.daily.name
  arn  = aws_lambda_function.fetch.arn
}

resource "aws_lambda_permission" "daily" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fetch.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily.arn
}

output "landing_bucket" {
  value = aws_s3_bucket.landing.id
}
