# Spec 01 step 4: the warehouse, catalog, schemas, read-only service principal, grants, and
# secret scope. Signs in with the CLI profile from `databricks auth login`; nothing secret here.

terraform {
  required_version = ">= 1.6"
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.140"
    }
  }
}

provider "databricks" {
  profile   = "workforce"
  auth_type = "databricks-cli" # never the service principal's DATABRICKS_CLIENT_* from .env
}

variable "warehouse_id" {
  description = "Id of the trial's existing warehouse, from `databricks warehouses list -p workforce`"
  type        = string
}

# The trial allows one warehouse, so adopt the auto-created one instead of creating a second.
import {
  to = databricks_sql_endpoint.workforce
  id = var.warehouse_id
}

resource "databricks_sql_endpoint" "workforce" {
  name                      = "workforce"
  cluster_size              = "2X-Small"
  min_num_clusters          = 1
  max_num_clusters          = 1
  auto_stop_mins            = 5
  enable_serverless_compute = true
  warehouse_type            = "PRO"
}

# The API cannot create a default-storage catalog without a location, so spec 01 step 4 creates it
# in SQL (`CREATE CATALOG workforce COMMENT ...`) and Terraform adopts it here.
import {
  to = databricks_catalog.workforce
  id = "workforce"
}

# force_destroy lets teardown drop it with data inside. A name change also replaces it and wipes
# the data; acceptable because everything reloads from the public APIs.
resource "databricks_catalog" "workforce" {
  name          = "workforce"
  comment       = "Federal workforce-risk briefing agent: OPM FWD and USAJOBS"
  force_destroy = true

  lifecycle {
    # Server-assigned on default storage: the S3 root, and a collation property.
    ignore_changes = [storage_root, properties]
  }
}

locals {
  schemas = {
    bronze   = "Raw OPM FWD and USAJOBS files, versioned as received"
    silver   = "Typed, deduplicated tables with stable keys"
    semantic = "Ontology-like layer: governed views and functions the agent may call"
    eval     = "Golden questions, per-run results, dashboard source"
  }
}

resource "databricks_schema" "this" {
  for_each      = local.schemas
  catalog_name  = databricks_catalog.workforce.name
  name          = each.key
  comment       = each.value
  force_destroy = true
}

# The agent's only identity. It reads; it holds no write grant anywhere.
resource "databricks_service_principal" "agent" {
  display_name          = "workforce-agent"
  databricks_sql_access = true # Genie consumers need it
}

# databricks_grant owns one principal's grants on one object; other principals' grants survive.
resource "databricks_grant" "agent_catalog" {
  catalog    = databricks_catalog.workforce.name
  principal  = databricks_service_principal.agent.application_id
  privileges = ["USE_CATALOG"]
}

resource "databricks_grant" "agent_silver" {
  schema     = databricks_schema.this["silver"].id
  principal  = databricks_service_principal.agent.application_id
  privileges = ["USE_SCHEMA"] # add "SELECT" only if spec 01 step 9 shows functions need it
}

# EXECUTE on the schema covers every function in it, now and later: semantic is the agent's surface.
resource "databricks_grant" "agent_semantic" {
  schema     = databricks_schema.this["semantic"].id
  principal  = databricks_service_principal.agent.application_id
  privileges = ["USE_SCHEMA", "EXECUTE"]
}

resource "databricks_secret_scope" "workforce" {
  name = "workforce"
}

output "agent_application_id" {
  description = "OAuth client id for .env; never commit it"
  value       = databricks_service_principal.agent.application_id
}
