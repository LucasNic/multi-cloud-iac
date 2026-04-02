include "root" {
  path = find_in_parent_folders()
}

dependency "networking" {
  config_path = "../networking"
}

terraform {
  source = "../../../../../modules/gcp/gke"
}

inputs = {
  gcp_project_id      = get_env("GCP_PROJECT_ID")
  zone                = "us-central1-a"
  vpc_name            = dependency.networking.outputs.vpc_name
  subnet_name         = dependency.networking.outputs.gke_subnet_name
  pods_range_name     = dependency.networking.outputs.pods_range_name
  services_range_name = dependency.networking.outputs.services_range_name
  node_count          = 1
}
