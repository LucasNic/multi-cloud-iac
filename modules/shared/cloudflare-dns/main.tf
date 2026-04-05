###############################################################################
# Cloudflare DNS + Workers — Automated Failover
#
# This module replaces Route53 as the DNS and failover layer.
# Cloudflare sits OUTSIDE both Azure and GCP, eliminating the single-point-of-failure
# that existed when Route53 (an AWS service) was used to trigger failover.
#
# Components:
# 1. DNS zone management (lucasnicoloso.com)
# 2. DNS records for AKS (primary) and GKE (failover) ingress IPs
# 3. Cloudflare Worker (JavaScript) that runs every minute, checks AKS health,
#    and updates the DNS A record if AKS is unhealthy
# 4. KV namespace to store failover state between Worker executions
#
# Cost: $0 (Workers free tier: 100k req/day, 3 cron triggers)
#
# Trade-off documented in ADR-007:
# Cloudflare Load Balancing ($5/month) would provide sub-second health checks
# and zero-downtime routing. The Workers cron approach has a minimum 1-minute
# detection interval, resulting in ~4 min RTO vs ~2.5 min with Load Balancing.
# This trade-off is acceptable for a portfolio workload at R$0/month cost.
###############################################################################

# --- DNS Zone ---

data "cloudflare_zone" "main" {
  name = var.domain_name
}

# --- DNS Records ---

# api.lucasnicoloso.com — managed by Worker failover (switches between AKS/GKE)
resource "cloudflare_record" "api_primary" {
  zone_id = data.cloudflare_zone.main.id
  name    = "api"
  type    = "A"
  content = local.app_ip
  proxied = true
  ttl     = 1
  comment = "AKS primary ingress — managed by Terraform, updated by Worker on failover"
}

# app.lucasnicoloso.com — frontend + backend served from AKS ingress
resource "cloudflare_record" "app" {
  zone_id = data.cloudflare_zone.main.id
  name    = "app"
  type    = "A"
  content = local.app_ip
  proxied = true
  ttl     = 1
  comment = "App subdomain — AKS nginx ingress"
}

locals {
  # Use explicit app_ingress_ip if provided, otherwise fall back to aks_ingress_ip
  app_ip = var.app_ingress_ip != "" ? var.app_ingress_ip : var.aks_ingress_ip
}

# Health endpoint records (not proxied — direct for Worker health checks)
resource "cloudflare_record" "aks_health" {
  zone_id = data.cloudflare_zone.main.id
  name    = "aks-health"
  type    = "A"
  content = var.aks_ingress_ip
  proxied = false
  ttl     = 60
  comment = "AKS direct health check endpoint — not proxied"
}

resource "cloudflare_record" "gke_health" {
  zone_id = data.cloudflare_zone.main.id
  name    = "gke-health"
  type    = "A"
  content = var.gke_ingress_ip
  proxied = false
  ttl     = 60
  comment = "GKE direct health check endpoint — not proxied"
}

# Root domain → portfolio site on Cloudflare Pages (CNAME flattening at root)
resource "cloudflare_record" "root" {
  zone_id         = data.cloudflare_zone.main.id
  name            = "@"
  type            = "CNAME"
  content         = var.root_cname_target
  proxied         = true
  ttl             = 1
  allow_overwrite = true
  comment         = "Root domain — portfolio on Cloudflare Pages"
}

# --- KV Namespace: stores failover state between Worker executions ---
#
# The Worker writes to KV: { current_target: "aks" | "gke", failure_count: N }
# This persists state across the 1-minute cron interval.

resource "cloudflare_workers_kv_namespace" "failover_state" {
  account_id = var.cloudflare_account_id
  title      = "${var.project_prefix}-failover-state"
}

# --- Worker Script ---

resource "cloudflare_worker_script" "failover" {
  account_id = var.cloudflare_account_id
  name       = "${var.project_prefix}-failover-worker"
  content    = file("${path.module}/worker/failover.js")
  module     = true

  kv_namespace_binding {
    name         = "FAILOVER_STATE"
    namespace_id = cloudflare_workers_kv_namespace.failover_state.id
  }

  plain_text_binding {
    name = "ZONE_ID"
    text = data.cloudflare_zone.main.id
  }

  plain_text_binding {
    name = "RECORD_NAME"
    text = "api"
  }

  plain_text_binding {
    name = "AKS_IP"
    text = var.aks_ingress_ip
  }

  plain_text_binding {
    name = "GKE_IP"
    text = var.gke_ingress_ip
  }

  plain_text_binding {
    name = "HEALTH_PATH"
    text = var.health_check_path
  }

  plain_text_binding {
    name = "FAILURE_THRESHOLD"
    text = tostring(var.failure_threshold)
  }

  secret_text_binding {
    name = "CF_API_TAKSN"
    text = var.cloudflare_api_token
  }

  secret_text_binding {
    name = "WORKER_SECRET"
    text = var.worker_secret
  }
}

# --- Worker Cron Trigger: runs every minute ---

resource "cloudflare_worker_cron_trigger" "failover" {
  account_id  = var.cloudflare_account_id
  script_name = cloudflare_worker_script.failover.name

  schedules = ["* * * * *"]  # Every minute — minimum interval on free tier
}

# --- Variables ---

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit + Workers permissions"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Root domain (e.g. lucasnicoloso.com)"
  type        = string
  default     = "lucasnicoloso.com"
}

variable "project_prefix" {
  type = string
}

variable "aks_ingress_ip" {
  description = "AKS primary cluster ingress public IP"
  type        = string
}

variable "gke_ingress_ip" {
  description = "GKE failover cluster ingress public IP"
  type        = string
}

variable "health_check_path" {
  description = "HTTP path for health checks (must return 200 when healthy)"
  type        = string
  default     = "/healthz"
}

variable "failure_threshold" {
  description = "Number of consecutive failures before triggering failover"
  type        = number
  default     = 3
}

variable "worker_secret" {
  description = "Bearer token to authenticate HTTP POST /trigger calls to the Worker"
  type        = string
  sensitive   = true
}

variable "root_cname_target" {
  description = "CNAME target for the root domain (e.g. Cloudflare Pages subdomain)"
  type        = string
  default     = "lucasnicoloso-com.pages.dev"
}

variable "app_ingress_ip" {
  description = "Ingress IP for app.lucasnicoloso.com (actual nginx LoadBalancer IP)"
  type        = string
  default     = ""
}

# --- Outputs ---

output "zone_id" {
  value = data.cloudflare_zone.main.id
}

output "worker_name" {
  value = cloudflare_worker_script.failover.name
}

output "api_fqdn" {
  value = "api.${var.domain_name}"
}

output "kv_namespace_id" {
  value = cloudflare_workers_kv_namespace.failover_state.id
}

output "worker_url" {
  description = "HTTP endpoint of the failover worker (used by backend to trigger instant failover)"
  value       = "https://${cloudflare_worker_script.failover.name}.${var.cloudflare_account_subdomain}.workers.dev"
}

variable "cloudflare_account_subdomain" {
  description = "workers.dev subdomain (e.g. lunicnic for lunicnic.workers.dev)"
  type        = string
  default     = "lunicnic"
}
