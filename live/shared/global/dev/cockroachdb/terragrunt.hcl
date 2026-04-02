include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../../modules/shared/cockroachdb"
}

inputs = {
  db_name     = "appdb"
  db_username = "appuser"
  db_password = get_env("COCKROACHDB_PASSWORD")

  cockroach_regions = ["gcp-us-east1", "gcp-us-central1"]
}
