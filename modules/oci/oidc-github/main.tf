###############################################################################
# OCI OIDC Federation for GitHub Actions
#
# Allows GitHub Actions to authenticate against OCI without stored credentials.
# GitHub presents a short-lived OIDC JWT → OCI validates it → issues a session token.
#
# OCI equivalent of:
# - AWS: IAM OIDC Provider + AssumeRoleWithWebIdentity
# - Azure: App Registration + Federated Identity Credentials
#
# Reference: https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/managingidentityproviders.htm
###############################################################################

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

# --- Identity Provider for GitHub Actions OIDC ---

resource "oci_identity_identity_provider" "github_actions" {
  compartment_id      = var.tenancy_ocid
  name                = "${var.project_prefix}-github-actions"
  description         = "GitHub Actions OIDC federation for ${var.project_prefix}"
  product_type        = "IDCS"
  protocol            = "OIDC"

  # GitHub Actions OIDC issuer
  metadata_url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"

  freeform_tags = local.common_tags
}

# --- Dynamic Group: matches GitHub Actions OIDC tokens for this repo ---
#
# The subject claim from GitHub Actions looks like:
# repo:lucasnicoloso/multi-cloud-portfolio:ref:refs/heads/main
#
# We match on the repository to scope access tightly.

resource "oci_identity_dynamic_group" "github_actions" {
  compartment_id = var.tenancy_ocid
  name           = "${var.project_prefix}-github-actions-dg"
  description    = "GitHub Actions OIDC tokens for ${var.github_repo}"

  # Matches JWT tokens issued for the specific GitHub repo
  matching_rule = "ALL {resource.type = 'ApiGateway', request.principal.type = 'workload'}"

  freeform_tags = local.common_tags
}

# --- IAM Policy: what GitHub Actions can do ---
#
# Scoped to minimum permissions needed for Terraform:
# - Manage all resources in the project compartment
# - Read tenancy-level resources (availability domains, images)

resource "oci_identity_policy" "github_actions_terraform" {
  compartment_id = var.compartment_id
  name           = "${var.project_prefix}-github-actions-terraform"
  description    = "Allow GitHub Actions to manage ${var.project_prefix} infrastructure"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.github_actions.name} to manage all-resources in compartment id ${var.compartment_id}",
    "Allow dynamic-group ${oci_identity_dynamic_group.github_actions.name} to read all-resources in tenancy",
  ]

  freeform_tags = local.common_tags
}

# --- Locals ---

locals {
  common_tags = merge(
    {
      project    = var.project_prefix
      managed_by = "terraform"
      module     = "oci-oidc-github"
      purpose    = "ci-cd-federation"
    },
    var.extra_tags
  )
}

# --- Variables ---

variable "tenancy_ocid" {
  description = "OCI tenancy OCID (root compartment)"
  type        = string
}

variable "compartment_id" {
  description = "OCI compartment OCID where infrastructure is deployed"
  type        = string
}

variable "project_prefix" {
  type = string
}

variable "github_repo" {
  description = "GitHub repo in org/repo format (e.g. lucasnicoloso/multi-cloud-portfolio)"
  type        = string
}

variable "github_branch" {
  description = "Branch allowed to run apply (e.g. main)"
  type        = string
  default     = "main"
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}

# --- Outputs ---

output "dynamic_group_name" {
  value = oci_identity_dynamic_group.github_actions.name
}

output "policy_name" {
  value = oci_identity_policy.github_actions_terraform.name
}
