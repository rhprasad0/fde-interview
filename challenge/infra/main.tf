# Spec 06: the Postgres the semantic layer lives on, replacing the Databricks workspace torn down 2026-11-02.
#
#   terraform init && terraform apply            # terraform.tfvars (gitignored) holds my_ip = "<laptop>/32"
#   terraform output -raw pg_env >> ../.env      # PG* (owner), AGENT_PG* (read-only agent), REVIEWER_PG* (app decisions)
#
# The agent, loader, and eval harness connect from the laptop, so the instance is public behind one /32 and a
# password; the OPM watcher's loader (pipeline.tf) gets in by security group. db.t4g.micro + 20 GB gp3 is about
# $14/month; destroy when done.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    archive = { source = "hashicorp/archive", version = "~> 2.7" }
  }
}

provider "aws" {
  region  = "us-west-2"
  profile = "nova-toll-dev"
}

variable "my_ip" {
  type        = string
  description = "Laptop address as a /32, e.g. from curl checkip.amazonaws.com"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_db_subnet_group" "workforce" {
  name       = "workforce"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_security_group" "pg" {
  name   = "workforce-pg"
  vpc_id = data.aws_vpc.default.id
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  ingress { # inline, so a separate rule resource is not stripped on the next apply
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.pipeline.id] # the OPM watcher's loader (pipeline.tf)
  }
}

resource "random_password" "master" {
  length  = 32
  special = false # RDS forbids / @ " and space
}

resource "random_password" "agent" {
  length  = 32
  special = false
}

resource "random_password" "reviewer" {
  length  = 32
  special = false
}

resource "aws_db_instance" "workforce" {
  identifier              = "workforce"
  engine                  = "postgres"
  engine_version          = "17"
  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  storage_type            = "gp3"
  db_name                 = "workforce" # so workforce.synthetic.x three-part names in truth SQL resolve
  username                = "workforce"
  password                = random_password.master.result
  db_subnet_group_name    = aws_db_subnet_group.workforce.name
  vpc_security_group_ids  = [aws_security_group.pg.id]
  publicly_accessible     = true
  multi_az                = false
  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true
}

output "pg_env" {
  sensitive = true
  value     = <<-EOT
    PGHOST=${aws_db_instance.workforce.address}
    PGPORT=5432
    PGDATABASE=workforce
    PGUSER=workforce
    PGPASSWORD=${random_password.master.result}
    PGSSLMODE=require
    AGENT_PGUSER=agent
    AGENT_PGPASSWORD=${random_password.agent.result}
    REVIEWER_PGUSER=reviewer
    REVIEWER_PGPASSWORD=${random_password.reviewer.result}
    PIPELINE_PGUSER=pipeline
    PIPELINE_PGPASSWORD=${random_password.pipeline.result}
  EOT
}
