###############################################################################
# Azure AKS — PRIMARY Cluster (Active in Active-Passive Failover)
#
# This cluster is the primary. All production traffic routes here by default.
# GKE (GCP) acts as PASSIVE failover, receiving traffic only when Cloudflare
# Workers detect AKS degradation via health checks.
#
# Compute: default_node_pool (system, Standard_D2ps_v5) + spot node pool (workloads, Standard_D2ps_v5 spot ~70% cheaper)
# Identity: Azure AD Workload Identity (pod-level, equivalent to EKS IRSA)
#
# Cost breakdown:
# - AKS control plane: FREE
# - Spot node (Standard_B2s): ~R$45/month
# - Public IP: included with Standard LB
###############################################################################

resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.project_prefix}-${var.environment}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.project_prefix}-${var.environment}"
  kubernetes_version  = var.kubernetes_version

  # System-assigned managed identity — no client secrets to rotate
  # ADR-008: managed identity over service principal
  identity {
    type = "SystemAssigned"
  }

  # Enable OIDC issuer for Workload Identity (pod-level Azure IAM)
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name                 = "system"
    node_count           = var.node_count
    vm_size              = var.vm_size
    vnet_subnet_id       = var.aks_subnet_id
    os_disk_size_gb      = 30
    os_disk_type         = "Ephemeral"
    os_sku               = "Ubuntu"
    temporary_name_for_rotation = "temp"

    node_labels = {
      environment = var.environment
      role        = "system"
    }

    upgrade_settings {
      max_surge = "1"
    }
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    service_cidr      = "10.1.0.0/16"
    dns_service_ip    = "10.1.0.10"
  }

  # Maintenance window — avoid disruption during business hours (BRT)
  maintenance_window {
    allowed {
      day   = "Saturday"
      hours = [0, 1, 2, 3, 4]
    }
    allowed {
      day   = "Sunday"
      hours = [0, 1, 2, 3, 4]
    }
  }

  tags = local.common_tags
}

# --- Spot Node Pool ---
# default_node_pool doesn't support spot — spot requires a separate node pool.
# This pool runs all app workloads; system pods stay on the default (regular) pool.

resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  name                  = "spot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.vm_size
  node_count            = var.node_count
  vnet_subnet_id        = var.aks_subnet_id
  os_disk_size_gb       = 30
  os_disk_type          = "Ephemeral"
  mode                  = "User"

  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = -1  # pay up to on-demand price

  node_labels = {
    environment                               = var.environment
    role                                      = "workload"
    "kubernetes.azure.com/scalesetpriority"   = "spot"
  }

  node_taints = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]

  tags = local.common_tags
}

# --- Locals ---

locals {
  common_tags = merge(
    {
      project     = var.project_prefix
      environment = var.environment
      managed_by  = "terraform"
      module      = "aks"
      role        = "primary-cluster"
    },
    var.extra_tags
  )
}

# --- Variables ---

variable "project_prefix" { type = string }
variable "environment" {
  type    = string
  default = "dev"
}
variable "location" {
  type    = string
  default = "eastus"
}
variable "resource_group_name" { type = string }
variable "aks_subnet_id" { type = string }
variable "kubernetes_version" {
  type    = string
  default = "1.32"
}
variable "vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2ps_v5"
}
variable "node_count" {
  type    = number
  default = 1
}
variable "extra_tags" {
  type    = map(string)
  default = {}
}

# --- Outputs ---

output "cluster_name" { value = azurerm_kubernetes_cluster.main.name }
output "cluster_id" { value = azurerm_kubernetes_cluster.main.id }
output "cluster_endpoint" {
  value = azurerm_kubernetes_cluster.main.fqdn
}
output "cluster_public_ip" {
  description = "Public IP of the AKS load balancer (for Cloudflare DNS)"
  value       = tolist(azurerm_kubernetes_cluster.main.network_profile[0].load_balancer_profile[0].effective_outbound_ips)[0]
}
output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity configuration"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}
output "kube_config" {
  value     = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive = true
}
output "kubelet_identity_object_id" {
  value = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
