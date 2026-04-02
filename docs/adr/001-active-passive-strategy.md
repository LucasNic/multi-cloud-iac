# ADR-001: Active-Passive Multi-Cloud Strategy (OCI + GCP)

## Status
Accepted

## Context

This project requires a multi-cloud resilience architecture that:
- Survives a full primary cloud outage without human intervention
- Stays within a ~R$20/month budget
- Demonstrates production-grade patterns in a portfolio context

AWS and Azure were evaluated and discarded due to cost:
- EKS control plane: ~R$382/month (no free tier for managed Kubernetes)
- AKS: free control plane but node costs ~R$60/month, no credits available
- IBM Cloud IKS: free cluster is 30-day trial only, not permanent

OCI and GCP offer the required managed Kubernetes capabilities at near-zero cost.

## Decision

**Active-Passive failover** between:
- **Primary**: OCI (Oracle Cloud Infrastructure) — OKE + ARM A1 Flex
- **Failover**: GCP (Google Cloud Platform) — GKE + preemptible e2-small

Failover is triggered and managed by **Cloudflare Workers** at the DNS layer.

| Criteria | Active-Active | Active-Passive | Feature Distribution |
|---|---|---|---|
| Data consistency | Hard (multi-primary) | Simple (single DB) | Varies |
| Operational complexity | Very High | Medium | Low |
| Cost | 2× full capacity | 1.3× (passive is minimal) | 1× |
| Demonstrates resilience | Yes, hard to prove | Yes, clear failover flow | No |

Active-Passive was chosen because:
- Solves a **real problem** (cloud provider outage) with a **provable mechanism**
- Failover can be **demonstrated live** in an interview
- Data consistency is handled by CockroachDB (multi-region, not multi-primary writes)

## Why OCI as Primary

- OKE control plane: free
- ARM A1 Flex: 4 OCPU + 24GB RAM, always free (not a trial)
- Most generous free tier compute of any cloud provider
- Sufficient for real application workloads

## Why GCP as Failover

- GKE Standard zonal: one free control plane per billing account
- Preemptible e2-small: ~R$20/month — the only cash cost in the architecture
- Tier-1 cloud provider, relevant for portfolio narrative

## Failover Timeline

| Phase | Duration | Cumulative |
|---|---|---|
| Cloudflare Worker health check | ~60s (1 min cron) | 60s |
| DNS propagation | ~60s (TTL=60) | 120s |
| **Total RTO** | | **~2 minutes** |

## Trade-offs

- (+) Clear architectural narrative with demonstrable failover
- (+) ~2 min RTO, testable on demand
- (+) CockroachDB handles data layer resilience independently
- (+) Total cost ~R$20/month
- (-) OCI has less market recognition than AWS
- (-) GCP preemptible nodes can be reclaimed by Google (mitigated: failover cluster only)
- (-) Not true HA — there IS a ~2 min outage window during failover

## Cost Breakdown

| Resource | Monthly Cost |
|---|---|
| OCI OKE + ARM A1 | R$0 |
| GCP GKE control plane | R$0 |
| GCP e2-small preemptible | ~R$20 |
| CockroachDB Serverless | R$0 |
| Cloudflare Workers | R$0 |
| **Total** | **~R$20/month** |
