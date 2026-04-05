include "root" {
  path = find_in_parent_folders()
}

dependency "azure_networking" {
  config_path = "../../../../azure/eastus/dev/networking"
  mock_outputs = {
    aks_ingress_ip    = "0.0.0.0"
    aks_ingress_pip_id = "/subscriptions/mock/resourceGroups/mock/providers/Microsoft.Network/publicIPAddresses/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "gcp_networking" {
  config_path = "../../../../gcp/us-central1/dev/networking"
  mock_outputs = {
    gke_ingress_ip = "0.0.0.0"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../../../../../modules/shared/cloudflare-dns"
}

inputs = {
  cloudflare_account_id = get_env("CLOUDFLARE_ACCOUNT_ID")
  cloudflare_api_token  = get_env("CLOUDFLARE_API_TOKEN")
  domain_name           = "lucasnicoloso.com"
  aks_ingress_ip        = dependency.azure_networking.outputs.aks_ingress_ip
  gke_ingress_ip        = dependency.gcp_networking.outputs.gke_ingress_ip
  # Actual nginx LoadBalancer IP (dynamic — AKS static IP is in wrong RG)
  app_ingress_ip        = "20.72.144.57"
  # Root domain points to portfolio on Cloudflare Pages
  root_cname_target     = "lucasnicoloso-com.pages.dev"
  failure_threshold     = 3
  worker_secret         = get_env("WORKER_SECRET")
}
