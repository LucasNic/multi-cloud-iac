###############################################################################
# GCP Workload Identity Federation for GitHub Actions
#
# Allows GitHub Actions to authenticate against GCP without stored credentials.
# GitHub presents a short-lived OIDC JWT → GCP validates it → issues a token
# bound to a Service Account.
#
# Reference: https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines
###############################################################################

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# --- Workload Identity Pool ---

resource "google_iam_workload_identity_pool" "github_actions" {
  project                   = var.gcp_project_id
  workload_identity_pool_id = "${var.project_prefix}-github"
  display_name              = "GitHub Actions — ${var.project_prefix}"
  description               = "OIDC federation for GitHub Actions CI/CD"
}

# --- Workload Identity Provider ---

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  project                            = var.gcp_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Actions OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # Map GitHub claims to Google attributes
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Restrict to specific repository only
  attribute_condition = "attribute.repository == '${var.github_repo}'"
}

# --- Service Account for Terraform ---

resource "google_service_account" "terraform" {
  project      = var.gcp_project_id
  account_id   = "${var.project_prefix}-terraform"
  display_name = "Terraform Service Account — ${var.project_prefix}"
  description  = "Used by GitHub Actions via Workload Identity Federation"
}

# --- IAM: allow GitHub Actions to impersonate the Service Account ---
#
# Only the main branch can run apply. PRs get plan-only via separate binding.

resource "google_service_account_iam_binding" "github_actions_apply" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/${var.github_repo}",
  ]
}

# --- IAM: grant Terraform Service Account permissions ---

resource "google_project_iam_member" "terraform_editor" {
  project = var.gcp_project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

resource "google_project_iam_member" "terraform_iam_admin" {
  project = var.gcp_project_id
  role    = "roles/iam.securityAdmin"
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# --- Variables ---

variable "gcp_project_id" { type = string }
variable "project_prefix" { type = string }
variable "github_repo" {
  description = "GitHub repo in org/repo format (e.g. lucasnicoloso/multi-cloud-portfolio)"
  type        = string
}

# --- Outputs ---

output "workload_identity_provider" {
  description = "Full provider resource name — used in GitHub Actions workflow"
  value       = google_iam_workload_identity_pool_provider.github_actions.name
}

output "service_account_email" {
  description = "Service account email — used in GitHub Actions workflow"
  value       = google_service_account.terraform.email
}
