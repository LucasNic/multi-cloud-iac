include "root" {
  path = find_in_parent_folders()
}

# Bootstrap-only module — excluded from CI run-all.
# Must be applied manually once with az login (requires Azure AD admin privileges).
# The CI Service Principal (Contributor role) cannot manage Azure AD applications.
skip = true

terraform {
  source = "../../../../../modules/azure/oidc-github"
}

inputs = {
  github_repo         = "LucasNic/multi-cloud-resilience-platform"
  github_branch       = "main"
  github_environments = ["production"]
}
