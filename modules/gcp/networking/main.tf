###############################################################################
# GCP Networking — VPC for GKE Failover Cluster
#
# Minimal VPC for the passive GKE cluster.
# All resources are within GCP free tier or minimal cost.
###############################################################################

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

resource "google_compute_network" "main" {
  name                    = "${var.project_prefix}-${var.environment}-vpc"
  auto_create_subnetworks = false
  project                 = var.gcp_project_id
}

resource "google_compute_subnetwork" "gke" {
  name          = "${var.project_prefix}-${var.environment}-gke-subnet"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.region
  network       = google_compute_network.main.id
  project       = var.gcp_project_id

  # Secondary ranges for GKE pods and services
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.2.0.0/20"
  }
}

# --- Firewall: allow HTTPS inbound (health checks + traffic) ---

resource "google_compute_firewall" "allow_https" {
  name    = "${var.project_prefix}-${var.environment}-allow-https"
  network = google_compute_network.main.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]
}

# --- Firewall: allow GCP health checks to reach nodes ---

resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.project_prefix}-${var.environment}-allow-hc"
  network = google_compute_network.main.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
  }

  # GCP health checker IP ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["gke-node"]
}

# --- Variables ---

variable "project_prefix" { type = string }
variable "environment" { type = string; default = "dev" }
variable "gcp_project_id" { type = string }
variable "region" { type = string; default = "us-central1" }

# --- Outputs ---

output "vpc_name" { value = google_compute_network.main.name }
output "vpc_id" { value = google_compute_network.main.id }
output "gke_subnet_name" { value = google_compute_subnetwork.gke.name }
output "gke_subnet_id" { value = google_compute_subnetwork.gke.id }
output "pods_range_name" { value = "gke-pods" }
output "services_range_name" { value = "gke-services" }
