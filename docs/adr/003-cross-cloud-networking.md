# ADR-003: Cross-Cloud Networking via Public Endpoints + TLS

## Status
Accepted

## Context

OCI (primary) and GCP (failover) are independent clouds with no native private
interconnect. Both clusters need to reach CockroachDB Serverless (external SaaS).

Options considered:
1. **Private interconnect** (OCI FastConnect + GCP Interconnect): $35-75/month each
2. **VPN tunnels** between clouds: operational complexity, ~$10-20/month
3. **Public endpoints + TLS + IP restriction**: zero cost, simple

## Decision

All cross-cloud communication uses **HTTPS over public internet** with:
- TLS enforced end-to-end
- CockroachDB connection string uses TLS with certificate verification
- Cloudflare proxies inbound traffic (hides origin IPs)

### Connections

| From | To | Protocol | Auth |
|---|---|---|---|
| OKE pods | CockroachDB Serverless | PostgreSQL/TLS | DB credentials via K8s Secret |
| GKE pods | CockroachDB Serverless | PostgreSQL/TLS | DB credentials via K8s Secret |
| Cloudflare Worker | OKE ingress `/healthz` | HTTPS | None (public endpoint) |
| Cloudflare Worker | GKE ingress `/healthz` | HTTPS | None (public endpoint) |
| GitHub Actions | OCI API | HTTPS | OIDC token |
| GitHub Actions | GCP API | HTTPS | OIDC token |

## Trade-offs

- (+) Zero additional infrastructure cost
- (+) Simple to debug and operate
- (+) CockroachDB Serverless manages its own TLS certificates
- (-) Higher latency than private interconnect (~5-15ms added)
- (-) Health endpoints are publicly reachable (mitigated: return only 200/503, no data)
