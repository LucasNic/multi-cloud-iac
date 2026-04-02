# Runbook: EKS Primary Cluster Failure → AKS Failover

## Scenario
The EKS primary cluster becomes unreachable. This document describes what breaks, how it's detected, and how traffic recovers — automatically.

## Architecture Context

```
Normal operation:
  Users → Route53 → EKS (PRIMARY) → RDS PostgreSQL

During failover:
  Users → Route53 → AKS (FAILOVER) → RDS PostgreSQL (cross-cloud, +50ms latency)
```

## Timeline of Events

### T+0s — EKS Becomes Unhealthy

**What breaks:**
- EKS API server is unreachable, OR
- Application pods crash-loop, OR
- ALB/NLB health checks fail, OR
- The `/healthz` endpoint returns non-200

**What does NOT break:**
- RDS PostgreSQL (independent of EKS, Multi-AZ within AWS)
- AKS cluster (independent infrastructure in Azure)
- ArgoCD (deployed in both clusters, self-healing)
- DNS resolution (Route53 is globally distributed)

### T+30s — First Health Check Fails

Route53 health checkers in 3 regions (us-east-1, eu-west-1, ap-southeast-1) each send an HTTPS request to the EKS ingress `/healthz` endpoint. The first check fails.

**Detection mechanism:**
```
Route53 Health Check Configuration:
  Target:     https://<eks-ingress>/healthz
  Interval:   30 seconds
  Threshold:  3 consecutive failures
  Regions:    3 (majority must agree)
```

### T+90s — EKS Marked UNHEALTHY

After 3 consecutive failures (30s × 3 = 90s), Route53 marks the EKS health check as UNHEALTHY.

**Automated actions triggered:**
1. CloudWatch alarm `multicloud-dev-failover-triggered` fires
2. SNS notification sent to on-call (PagerDuty/Slack/email)
3. Route53 stops returning EKS IP for `api.example.com`
4. Route53 starts returning AKS IP for `api.example.com`

### T+150s (~2.5 min) — Traffic Flowing to AKS

DNS propagation completes (TTL=60s). All new DNS lookups resolve to the AKS failover cluster.

**Expected degradation during failover:**
- Database latency increases by ~50ms (cross-cloud: Azure → AWS RDS)
- Some clients may cache the old DNS for up to 60s beyond TTL
- No data loss (single RDS source of truth, SSL-enforced connections)

**What works immediately on AKS:**
- Same application version (ArgoCD keeps both clusters in sync)
- Same database (RDS endpoint is accessible from AKS via public endpoint + SG)
- Same secrets (ExternalSecret operator pulls from cloud-native secret stores)

### T+??? — EKS Recovers

When EKS becomes healthy again:
1. Route53 health checks pass (3 consecutive successes)
2. Route53 automatically fails BACK to EKS (primary)
3. CloudWatch alarm returns to OK state
4. SNS notification confirms recovery

**Manual verification before failback (recommended):**
```bash
# Verify EKS cluster health
kubectl --context eks get nodes
kubectl --context eks get pods -n app

# Verify application health
curl -v https://<eks-ingress>/healthz

# Check ArgoCD sync status
argocd app get api-eks-primary
```

## Key Metrics to Monitor

| Metric | Source | Alert Threshold |
|---|---|---|
| Route53 health check status | CloudWatch | < 1 (unhealthy) |
| API response latency (p99) | Prometheus | > 500ms (normal) / > 800ms (failover) |
| Error rate (5xx) | Prometheus/ALB | > 1% |
| ArgoCD sync status | ArgoCD metrics | OutOfSync > 5 min |
| RDS connections | CloudWatch | > 80% of max |
| DNS resolution time | External monitoring | > 100ms |

## What Can Go Wrong During Failover

| Risk | Mitigation |
|---|---|
| AKS also down | Route53 checks AKS health independently; if both fail, returns last known good |
| RDS unreachable from AKS | Security group pre-configured with AKS outbound IPs; SSL cert pre-validated |
| ArgoCD out of sync | Automated sync with self-heal; Slack alert on OutOfSync > 5 min |
| DNS cache stale | TTL=60s minimizes window; CDN purge documented below |
| Connection pool exhaustion | AKS pods scale via HPA; RDS max_connections sized for dual-cluster load |

## Manual Intervention Procedures

### Force Failover (Testing or Planned Maintenance)

```bash
# Option 1: Disable EKS health check (triggers failover)
aws route53 update-health-check \
  --health-check-id HC_ID \
  --disabled

# Option 2: Scale EKS deployment to 0 (app-level failover)
kubectl --context eks scale deployment/api -n app --replicas=0

# Verify traffic is hitting AKS
curl -v https://api.example.com/healthz
# Should return AKS-specific headers or response
```

### Force Failback

```bash
# Re-enable EKS health check
aws route53 update-health-check \
  --health-check-id HC_ID \
  --no-disabled

# Verify EKS is healthy and receiving traffic
watch -n5 'curl -s https://api.example.com/healthz | jq .cluster_role'
```

### Purge CDN Cache After Failover

```bash
aws cloudfront create-invalidation \
  --distribution-id DIST_ID \
  --paths "/*"
```

## Post-Incident Review Checklist

- [ ] Root cause identified and documented
- [ ] Failover timeline matches expected RTO (~2.5 min)
- [ ] No data loss confirmed (RDS integrity check)
- [ ] ArgoCD sync status verified on both clusters
- [ ] Health check thresholds reviewed (too sensitive? too slow?)
- [ ] Runbook updated with lessons learned
