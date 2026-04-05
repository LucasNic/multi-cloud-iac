###############################################################################
# GCP GKE — PASSIVE Cluster (Failover in Active-Passive Architecture)
#
# This cluster receives production traffic ONLY when the primary OKE cluster
# fails Cloudflare Worker health checks. During normal operation, GKE is idle
# but kept warm with the same application version deployed via ArgoCD.
#
# Cost:
# - Control plane: FREE (one zonal cluster per billing account)
# - Node: e2-small preemptible — ~R$20/month (the only cash cost in the project)
#
# Identity: Workload Identity Federation (pod-level, equivalent to EKS IRSA)
###############################################################################

# --- GKE Cluster ---

resource "google_container_cluster" "main" {
  name             = "${var.project_prefix}-${var.environment}-gke"
  location         = var.zone  # Zonal cluster = free control plane
  project          = var.gcp_project_id
  min_master_version = var.kubernetes_version

  # Remove default node pool — we create a managed one below
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.vpc_name
  subnetwork = var.subnet_name

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Enable Workload Identity — pod-level GCP IAM (equivalent to EKS IRSA)
  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  # Private cluster endpoint — nodes have no public IPs
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false  # Public control plane endpoint for CI/CD
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all (restrict in prod)"
    }
  }

  # Logging and monitoring — use GCP managed (no extra cost)
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # Maintenance window — avoid disruption during business hours (BRT)
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T03:00:00Z"  # 00:00 BRT
      end_time   = "2024-01-01T07:00:00Z"  # 04:00 BRT
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  resource_labels = local.common_labels
}

# --- Node Pool: preemptible e2-small ---
#
# Preemptible = ~70% cheaper than on-demand.
# e2-small: 0.5-2 vCPU (burstable), 2GB RAM — sufficient for passive workloads.
# Risk: preemptible nodes can be reclaimed. Mitigated: this is the FAILOVER cluster.
# If a node gets reclaimed, GKE replaces it in ~90 seconds.

resource "google_container_node_pool" "main" {
  name     = "${var.project_prefix}-${var.environment}-pool"
  location = var.zone
  cluster  = google_container_cluster.main.name
  project  = var.gcp_project_id

  node_count = var.node_count

  node_config {
    machine_type = "e2-small"
    # spot = true requires PREEMPTIBLE_CPUS quota — quota is 0 on free accounts.
    # Using on-demand e2-small (~R$20/month) for the passive failover cluster.

    disk_size_gb = 30
    disk_type    = "pd-standard"

    # Workload Identity on the node
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = {
      environment = var.environment
      role        = "failover-cluster"
    }

    tags = ["gke-node", "${var.project_prefix}-${var.environment}"]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# --- Locals ---

locals {
  common_labels = merge(
    {
      project     = var.project_prefix
      environment = var.environment
      managed_by  = "terraform"
      module      = "gke"
      role        = "failover-cluster"
    },
    var.extra_labels
  )
}

# --- Variables ---

variable "project_prefix" { type = string }
variable "environment" {
  type    = string
  default = "dev"
}
variable "gcp_project_id" { type = string }
variable "zone" {
  description = "GCP zone for zonal cluster (free control plane)"
  type        = string
  default     = "us-central1-a"
}
variable "vpc_name" { type = string }
variable "subnet_name" { type = string }
variable "pods_range_name" { type = string }
variable "services_range_name" { type = string }
variable "node_count" {
  description = "Number of nodes (1 is sufficient for passive failover)"
  type        = number
  default     = 1
}
variable "kubernetes_version" {
  description = "GKE master version — use gcloud container get-server-config to list valid versions"
  type        = string
  default     = "1.32"
}
variable "extra_labels" {
  type    = map(string)
  default = {}
}

# --- Outputs ---

output "cluster_name" { value = google_container_cluster.main.name }
output "cluster_endpoint" { value = google_container_cluster.main.endpoint }
output "cluster_ca_certificate" {
  value     = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive = true
}
output "workload_identity_pool" {
  value = "${var.gcp_project_id}.svc.id.goog"
}
