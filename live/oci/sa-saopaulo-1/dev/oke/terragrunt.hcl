include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../../modules/oci/oke"
}

inputs = {
  compartment_id           = get_env("OCI_COMPARTMENT_ID")
  availability_domain      = get_env("OCI_AVAILABILITY_DOMAIN")
  object_storage_namespace = get_env("OCI_NAMESPACE")

  # ARM A1 free tier: 1 node with all 4 OCPU + 24GB
  node_count     = 1
  node_ocpus     = 4
  node_memory_gb = 24
}
