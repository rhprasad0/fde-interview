# The demo app on Lambda (DECISIONS.md, Deploy): the repo-root Dockerfile's image behind a streaming Function URL, with a
# Cloudflare Worker on the custom domain passing requests through. The function sits in the VPC to reach RDS and leaves
# it over IPv6 through an egress-only gateway (the Anthropic API and SSM's dual-stack endpoint both answer on IPv6), so
# there is no NAT gateway. Two new dual-stack subnets keep the default VPC's own subnets and route table untouched.
#
#   terraform apply -target=aws_ecr_repository.app              # once, for the repository
#   docker build --platform linux/amd64 --build-arg AGENT_GIT_SHA=$(git rev-parse HEAD) -t <repo>:<tag> ../.. && docker push <repo>:<tag>
#   terraform apply                                             # app_image_tag = "<tag>" in terraform.tfvars
# The Anthropic key is an SSM SecureString (/lantern/anthropic-api-key, us-west-2) put there by hand; the app reads it
# at startup, so it is in neither the function's environment nor this state.

variable "app_image_tag" {
  type        = string
  description = "Tag of the image in the lantern ECR repository"
}

locals {
  anthropic_key_param = "/lantern/anthropic-api-key"
  app_subnets         = { "us-west-2a" = 64, "us-west-2b" = 65 } # 172.31.64.0/24 and .65.0/24; the default /20s end at .63
}

data "aws_caller_identity" "current" {}

data "aws_internet_gateway" "default" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_ecr_repository" "app" {
  name         = "lantern"
  force_delete = true # destroy when done, like the instance
}

# --- network: dual-stack subnets with IPv6 egress only ---

resource "aws_vpc_ipv6_cidr_block_association" "default" {
  vpc_id                           = data.aws_vpc.default.id
  assign_generated_ipv6_cidr_block = true
}

resource "aws_egress_only_internet_gateway" "app" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_route_table" "app" {
  vpc_id = data.aws_vpc.default.id
  route {
    cidr_block = "0.0.0.0/0" # unused by the function (no public IPv4), kept so the table reads like the default one
    gateway_id = data.aws_internet_gateway.default.id
  }
  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.app.id
  }
}

resource "aws_subnet" "app" {
  for_each                        = local.app_subnets
  vpc_id                          = data.aws_vpc.default.id
  availability_zone               = each.key
  cidr_block                      = "172.31.${each.value}.0/24"
  ipv6_cidr_block                 = cidrsubnet(aws_vpc_ipv6_cidr_block_association.default.ipv6_cidr_block, 8, each.value)
  assign_ipv6_address_on_creation = true
}

resource "aws_route_table_association" "app" {
  for_each       = aws_subnet.app
  subnet_id      = each.value.id
  route_table_id = aws_route_table.app.id
}

resource "aws_security_group" "app" {
  name   = "lantern-app"
  vpc_id = data.aws_vpc.default.id
  egress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"] # the Anthropic API and SSM
  }
  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
}

# --- the function ---

resource "aws_iam_role" "app" {
  name               = "lantern-app"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "app" {
  statement {
    actions   = ["ssm:GetParameter"] # the AWS-managed aws/ssm key needs no kms grant
    resources = ["arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${local.anthropic_key_param}"]
  }
}

data "aws_region" "current" {}

resource "aws_iam_role_policy" "app" {
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/lambda/lantern"
  retention_in_days = 14
}

resource "aws_lambda_function" "app" {
  function_name = "lantern"
  role          = aws_iam_role.app.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.app.repository_url}:${var.app_image_tag}"
  architectures = ["x86_64"]
  memory_size   = 2048 # CPU scales with memory; the imports and the trace writer are the cold start
  timeout       = 900  # an xhigh turn runs up to about 300 s
  vpc_config {
    subnet_ids                  = [for s in aws_subnet.app : s.id]
    security_group_ids          = [aws_security_group.app.id]
    ipv6_allowed_for_dual_stack = true
  }
  environment {
    # The agent and reviewer roles only; the owner never leaves the laptop. Passwords as encrypted env vars, as on the loader.
    variables = {
      PGHOST                = aws_db_instance.workforce.address
      PGPORT                = "5432"
      PGDATABASE            = "workforce"
      PGSSLMODE             = "require"
      AGENT_PGUSER          = "agent"
      AGENT_PGPASSWORD      = random_password.agent.result
      REVIEWER_PGUSER       = "reviewer"
      REVIEWER_PGPASSWORD   = random_password.reviewer.result
      ANTHROPIC_API_KEY_SSM = local.anthropic_key_param
      AWS_LWA_ASYNC_INIT    = "true" # boot outlasts Lambda's 10 s init; without this the init times out and reruns (24 s cold start)
    }
  }
  depends_on = [aws_iam_role_policy_attachment.app, aws_cloudwatch_log_group.app, aws_route_table_association.app]
}

resource "aws_lambda_function_url" "app" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE" # public; the Cloudflare Worker is the front door
  invoke_mode        = "RESPONSE_STREAM"
}

resource "aws_lambda_permission" "url" {
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.app.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "url_invoke" {
  action                   = "lambda:InvokeFunction" # function URLs also need this, scoped to calls through the URL
  function_name            = aws_lambda_function.app.function_name
  principal                = "*"
  invoked_via_function_url = true
}

output "app_url" {
  value = aws_lambda_function_url.app.function_url
}
