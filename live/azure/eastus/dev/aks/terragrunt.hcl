include "root" {
  path = find_in_parent_folders()
}

dependency "networking" {
  config_path = "../networking"
}

terraform {
  source = "../../../../../modules/azure/aks"
}

inputs = {
  location            = "eastus"
  resource_group_name = dependency.networking.outputs.resource_group_name
  aks_subnet_id       = dependency.networking.outputs.aks_subnet_id
  node_count          = 1
}
