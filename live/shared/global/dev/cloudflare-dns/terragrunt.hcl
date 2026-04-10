# ⚠️ ATENÇÃO: DEPLOY HABILITADO APENAS PARA DNS ⚠️
# Esta configuração está habilitada apenas para criar/atualizar registros DNS no Cloudflare.
# Os recursos de infraestrutura multi-cloud (AKS, GKE) permanecem desativados para evitar custos.
# O projeto multi-cloud agora é apenas uma demonstração visual hospedada no Cloudflare Pages.
# Execute terragrunt apply apenas para criar os registros DNS necessários.
# Repositório da simulação visual: https://github.com/LucasNic/multi-cloud-simulation (não existe - usar site principal temporariamente)

include "root" {
  path = find_in_parent_folders()
}


terraform {
  source = "../../../../../modules/shared/cloudflare-dns"

  extra_arguments "reconfigure" {
    commands = ["init"]
    arguments = ["-reconfigure"]
  }
}

remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {}
}

inputs = {
  cloudflare_account_id = get_env("CLOUDFLARE_ACCOUNT_ID")
  cloudflare_api_token  = get_env("CLOUDFLARE_API_TOKEN")
  domain_name           = "lucasnicoloso.com"
  # Usando valores hardcoded porque os módulos de networking foram destruídos/desativados
  aks_ingress_ip        = "20.72.144.57"  # IP do AKS (pode não existir mais)
  gke_ingress_ip        = "34.27.20.121"  # IP do GKE (pode não existir mais)
  app_ingress_ip        = "20.72.144.57"  # IP do AKS (mesmo que aks_ingress_ip)
  # Root domain points to portfolio on Cloudflare Pages
  root_cname_target     = "lucasnicoloso-com.pages.dev"
  failure_threshold     = 3
  worker_secret         = get_env("WORKER_SECRET")
}
