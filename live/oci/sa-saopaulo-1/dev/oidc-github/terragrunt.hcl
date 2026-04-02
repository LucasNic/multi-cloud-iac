include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../../modules/oci/oidc-github"
}

inputs = {
  tenancy_ocid   = get_env("OCI_TENANCY_OCID")
  compartment_id = get_env("OCI_COMPARTMENT_ID")
  github_repo    = "lucasnicoloso/multi-cloud-portfolio"
  github_branch  = "main"
}
