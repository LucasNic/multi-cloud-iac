###############################################################################
# Observability Stack — Cloud-Agnostic Monitoring
#
# Deploys to BOTH clusters via Helm. Ensures consistent monitoring
# regardless of which cluster is actively serving traffic.
#
# Stack:
# - Prometheus (metrics collection + alerting rules)
# - Grafana (dashboards — optional, can use CloudWatch/Azure Monitor)
# - Fluent Bit (log forwarding to cloud-native sinks)
#
# This module outputs Helm values. Actual deployment is via ArgoCD.
###############################################################################

# --- Prometheus Alert Rules for Failover Monitoring ---

resource "local_file" "prometheus_rules" {
  filename = "${path.module}/output/prometheus-rules.yaml"
  content  = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "failover-alerts"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      groups = [
        {
          name = "failover.rules"
          rules = [
            {
              alert = "HighErrorRate"
              expr  = "sum(rate(http_requests_total{code=~\"5..\"}[5m])) / sum(rate(http_requests_total[5m])) > 0.01"
              for   = "2m"
              labels = { severity = "critical" }
              annotations = {
                summary     = "API error rate above 1%"
                description = "Error rate is {{ $value | humanizePercentage }}. If sustained, Route53 health check will trigger failover."
                runbook_url = "https://github.com/lucasnicoloso/multi-cloud-portfolio/blob/main/docs/runbooks/failover-scenario.md"
              }
            },
            {
              alert = "HighLatency"
              expr  = "histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 0.5"
              for   = "3m"
              labels = { severity = "warning" }
              annotations = {
                summary     = "API p99 latency above 500ms"
                description = "p99 latency is {{ $value }}s. Normal: <200ms (primary), <500ms (failover with cross-cloud DB)."
              }
            },
            {
              alert = "PodCrashLooping"
              expr  = "rate(kube_pod_container_status_restarts_total{namespace=\"app\"}[15m]) > 0"
              for   = "5m"
              labels = { severity = "critical" }
              annotations = {
                summary     = "Pod {{ $labels.pod }} is crash-looping"
                description = "This will degrade the /healthz endpoint and may trigger Route53 failover."
              }
            },
            {
              alert = "DatabaseConnectionFailure"
              expr  = "pg_up == 0"
              for   = "1m"
              labels = { severity = "critical" }
              annotations = {
                summary     = "Cannot connect to RDS PostgreSQL"
                description = "If this cluster is the active one, API requests will fail and Route53 will failover."
              }
            },
            {
              alert = "ClusterRoleMismatch"
              expr  = "count(kube_pod_labels{label_cluster_role=\"primary\"}) == 0 and count(kube_pod_labels{label_cluster_role=\"failover\"}) == 0"
              for   = "5m"
              labels = { severity = "warning" }
              annotations = {
                summary = "No pods have cluster-role label"
                description = "ArgoCD may not have synced the overlay correctly."
              }
            }
          ]
        }
      ]
    }
  })
}

# --- Helm Values for kube-prometheus-stack ---

resource "local_file" "prometheus_values" {
  filename = "${path.module}/output/prometheus-values.yaml"
  content  = yamlencode({
    prometheus = {
      prometheusSpec = {
        retention         = var.environment == "prod" ? "15d" : "3d"
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              accessModes = ["ReadWriteOnce"]
              resources   = { requests = { storage = var.environment == "prod" ? "50Gi" : "10Gi" } }
            }
          }
        }
        # Scrape app metrics
        additionalScrapeConfigs = [
          {
            job_name        = "api-pods"
            kubernetes_sd_configs = [{ role = "pod" }]
            relabel_configs = [
              {
                source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
                action        = "keep"
                regex         = "true"
              },
              {
                source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_port"]
                action        = "replace"
                target_label  = "__address__"
                regex         = "(.+)"
                replacement   = "$1"
              }
            ]
          }
        ]
      }
    }
    grafana = {
      enabled = var.deploy_grafana
      adminPassword = var.grafana_admin_password
    }
  })
}

# --- Fluent Bit Values (log forwarding) ---

resource "local_file" "fluentbit_values" {
  filename = "${path.module}/output/fluentbit-values.yaml"
  content  = yamlencode({
    config = {
      outputs = var.cloud == "aws" ? <<-AWSOUT
        [OUTPUT]
            Name cloudwatch_logs
            Match *
            region ${var.aws_region}
            log_group_name /eks/${var.project_prefix}-${var.environment}/app
            log_stream_prefix fluentbit-
            auto_create_group true
      AWSOUT
      : <<-AZUREOUT
        [OUTPUT]
            Name azure
            Match *
            Customer_ID ${var.log_analytics_workspace_id}
            Shared_Key ${var.log_analytics_key}
      AZUREOUT
    }
  })
}

variable "project_prefix" { type = string }
variable "environment" { type = string }
variable "cloud" { type = string; description = "aws or azure" }
variable "deploy_grafana" { type = bool; default = false }
variable "grafana_admin_password" { type = string; default = "admin"; sensitive = true }
variable "aws_region" { type = string; default = "us-east-1" }
variable "log_analytics_workspace_id" { type = string; default = "" }
variable "log_analytics_key" { type = string; default = ""; sensitive = true }

output "prometheus_rules_path" { value = local_file.prometheus_rules.filename }
output "prometheus_values_path" { value = local_file.prometheus_values.filename }
output "fluentbit_values_path" { value = local_file.fluentbit_values.filename }
