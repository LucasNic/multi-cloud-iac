# ADR-007: Cloudflare Workers for DNS Failover

## Status
Accepted

## Context

Replaces ADR-007 (Route53 DNS Failover).

Route53 was discarded for two reasons:
1. **Single point of failure**: Route53 is an AWS service. If AWS goes down,
   Route53 goes down too — the failover to GCP would never trigger.
2. **Cost**: Route53 health checks cost ~$2/month (minor but avoidable).

The DNS layer must be **outside both clouds** to be a reliable failover trigger.

## Decision

**Cloudflare Workers** with a cron trigger performs health checks and updates DNS.

### How It Works

1. A Cloudflare Worker runs every 60 seconds (cron trigger)
2. Worker checks `https://api.lucasnicoloso.com/healthz` → OKE ingress
3. If check fails 3 consecutive times → Worker updates the DNS A record to GKE IP
4. When OKE recovers and passes 3 checks → Worker fails back to OKE

```
Cloudflare (neutral)
  └── Worker (cron: every 1 min)
        ├── GET https://oci-ingress/healthz
        │     healthy → DNS = OKE IP (no change)
        │     unhealthy ×3 → DNS A record → GKE IP
        └── GET https://gke-ingress/healthz
              monitors failover cluster availability
```

### Why Workers over Cloudflare Load Balancing

Cloudflare Load Balancing costs $5/month (R$26/month at current rates).
Cloudflare Workers free tier: 100,000 requests/day, 3 cron triggers — sufficient.

**Trade-off documented**: Cloudflare Load Balancing is the production-grade solution
with sub-second health check intervals and zero-downtime routing. Workers with
1-minute cron is an acceptable portfolio approximation that keeps costs at R$0.

### Failover Timeline

| Phase | Duration | Cumulative |
|---|---|---|
| Worker detects failure (3 checks) | ~3 min | 3 min |
| DNS propagation (TTL=60) | ~1 min | 4 min |
| **Total RTO** | | **~4 minutes** |

Note: RTO is slightly higher than Route53 (~2.5 min) due to the 1-minute cron interval.
This is acceptable for a portfolio workload. Enterprise solution: Cloudflare Load Balancing.

### Why Cloudflare (Not Another DNS Provider)

- **Outside both clouds**: Cloudflare has no dependency on OCI or GCP
- **Terraform provider**: `cloudflare` provider manages DNS + Workers declaratively
- **Free tier**: DNS, Workers, and cron are all free at this scale
- **Proxy mode**: Cloudflare proxies traffic, hiding origin IPs from public internet

## Trade-offs

- (+) DNS layer is independent of both application clouds
- (+) Eliminates the Route53 SPOF from the original architecture
- (+) Worker code lives in the repo — reviewable, testable, version-controlled
- (+) Zero cost
- (-) 1-minute cron minimum interval (vs sub-second for paid Load Balancing)
- (-) RTO is ~4 minutes vs ~2.5 minutes with Route53/Load Balancing
- (-) Worker failure would disable automated failover (mitigated: Cloudflare SLA is 99.99%)
