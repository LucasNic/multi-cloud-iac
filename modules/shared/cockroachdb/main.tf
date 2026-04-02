###############################################################################
# CockroachDB Serverless — Multi-Region Database
#
# Replaces AWS RDS PostgreSQL. Rationale in ADR-005.
#
# CockroachDB Serverless free tier:
# - 5GB storage
# - 50M Request Units/month
# - Multi-region: data survives regional cloud outages
# - PostgreSQL wire-compatible: no application code changes needed
#
# Both OKE (primary) and GKE (failover) connect to the same CockroachDB
# endpoint. CockroachDB handles replication internally.
#
# Provider: https://registry.terraform.io/providers/cockroachdb/cockroach
###############################################################################

terraform {
  required_providers {
    cockroach = {
      source  = "cockroachdb/cockroach"
      version = "~> 1.0"
    }
  }
}

# --- Serverless Cluster ---

resource "cockroach_cluster" "main" {
  name           = "${var.project_prefix}-${var.environment}"
  cloud_provider = "GCP"  # CockroachDB hosted on GCP (closest to both OCI + GKE)

  serverless = {
    spend_limit = 0  # $0 spend limit = stay within free tier always
  }

  regions = var.cockroach_regions
}

# --- Database ---

resource "cockroach_database" "app" {
  name       = var.db_name
  cluster_id = cockroach_cluster.main.id
}

# --- SQL User for Application ---

resource "cockroach_sql_user" "app" {
  name       = var.db_username
  password   = var.db_password
  cluster_id = cockroach_cluster.main.id
}

# --- Variables ---

variable "project_prefix" { type = string }
variable "environment" { type = string; default = "dev" }

variable "cockroach_regions" {
  description = "CockroachDB regions for multi-region resilience"
  type        = list(string)
  # GCP regions chosen for proximity to OCI sa-saopaulo-1 and GKE us-central1
  default     = ["gcp-us-east1", "gcp-us-central1"]
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appuser"
}

variable "db_password" {
  type      = string
  sensitive = true
}

# --- Outputs ---

output "cluster_id" {
  value = cockroach_cluster.main.id
}

output "connection_string" {
  description = "PostgreSQL-compatible connection string (without password)"
  value       = "postgresql://${var.db_username}@${cockroach_cluster.main.name}.cockroachlabs.cloud:26257/${var.db_name}?sslmode=verify-full"
  sensitive   = false
}

output "cluster_host" {
  value = "${cockroach_cluster.main.name}.cockroachlabs.cloud"
}

output "db_port" {
  value = 26257
}

output "db_name" {
  value = var.db_name
}

output "db_username" {
  value = var.db_username
}
