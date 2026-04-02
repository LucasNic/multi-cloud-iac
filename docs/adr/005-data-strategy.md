# ADR-005: CockroachDB Serverless as Multi-Region Database

## Status
Accepted

## Context

Replaces ADR-005 (Single RDS PostgreSQL). RDS was discarded due to cost (~R$14/month,
expiring free tier) and inability to survive a regional failure.

Options evaluated:
1. **RDS PostgreSQL (AWS)**: ~R$14/month after free tier, single region, AWS dependency
2. **MongoDB Atlas M0**: free, but single region on free tier — no failover
3. **CockroachDB Serverless**: free tier (5GB, 50M RUs/month), multi-region native
4. **PlanetScale**: MySQL-compatible serverless, free tier, but single region
5. **Neon**: PostgreSQL serverless, free tier, but pauses after inactivity

## Decision

**CockroachDB Serverless** as the database layer.

### Why CockroachDB

- **PostgreSQL-compatible wire protocol**: application code needs no changes
- **Multi-region by design**: data survives regional cloud outages
- **Free tier is permanent**: 5GB storage + 50M Request Units/month, no expiry
- **Managed**: no infrastructure to operate, scales automatically
- **Terraform provider**: `cockroach` provider manages cluster + databases declaratively

### How It Fits the Failover Architecture

```
OCI (primary)          GCP (failover)
OKE pods               GKE pods
    |                      |
    └──────────┬────────────┘
               |
    CockroachDB Serverless
    (multi-region: us-east1 + us-central1)
```

Both OKE and GKE connect to the same CockroachDB endpoint via TLS.
CockroachDB handles replication internally — no split-brain risk.

### Failover Behavior

- If OCI goes down → GKE takes traffic → connects to same CockroachDB endpoint
- If one CockroachDB region goes down → CockroachDB routes to surviving region
- Application sees a momentary connection blip, then recovery

## Trade-offs

- (+) True multi-region database resilience at zero cost
- (+) No infrastructure to manage (fully serverless)
- (+) PostgreSQL-compatible — standard ORM/driver support
- (+) Demonstrates knowledge of distributed database systems
- (-) 50M RU/month limit on free tier (sufficient for portfolio traffic)
- (-) CockroachDB-specific SQL extensions exist (not pure PostgreSQL)
- (-) Slightly higher latency than co-located DB (~10-20ms)

## Note for Enterprise Context

In a production enterprise context, the choice would depend on existing cloud
contracts and data residency requirements. CockroachDB is production-grade and
used by companies like Netflix, Comcast, and DoorDash. This is not a portfolio
compromise — it is a legitimate architectural choice.
