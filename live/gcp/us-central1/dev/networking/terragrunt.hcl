include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../../modules/gcp/networking"
}

inputs = {
  gcp_project_id = get_env("GCP_PROJECT_ID")
}
