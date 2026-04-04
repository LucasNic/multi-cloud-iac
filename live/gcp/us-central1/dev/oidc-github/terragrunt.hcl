include "root" {
  path = find_in_parent_folders()
}

# Bootstrap-only module — excluded from CI run-all.
# Must be applied manually once (requires Project Owner/IAM Admin).
# The CI Service Account (roles/editor) cannot create Workload Identity Pools.
skip = true

terraform {
  source = "../../../../../modules/gcp/oidc-github"
}

inputs = {
  gcp_project_id = get_env("GCP_PROJECT_ID")
  github_repo    = "LucasNic/multi-cloud-resilience-platform"
}
