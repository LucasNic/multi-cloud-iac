# Platform Architecture — Multi-Cloud Resilient Infrastructure

## Purpose

This document defines the **infrastructure architecture and operational model** of the multi-cloud platform.

Focus areas:

- resilience
- failover
- infrastructure as code
- security
- cost-awareness

---

## Architecture Strategy

- Pattern: Active-Passive failover
- Primary cloud: AWS
- Secondary cloud: Azure
- Failover mechanism: DNS (Route53)
- RTO: ~2.5 minutes

---

## Core Components

### AWS (Primary)

- EKS (Kubernetes)
- RDS PostgreSQL (single source of truth)
- CloudFront (CDN)
- ALB (Ingress)
- Route53 (DNS + health checks)

---

### Azure (Failover)

- AKS (Kubernetes)
- NGINX Ingress
- System-Assigned Managed Identity

---

## Data Strategy

- Single database (RDS in AWS)
- AKS accesses DB via secure cross-cloud connection

Trade-off:
- no split-brain risk
- added latency (~50ms)

---

## Failover Flow

1. EKS becomes unhealthy
2. Route53 health checks fail (3 × 30s)
3. Route53 marks primary as unhealthy
4. DNS switches to AKS
5. Traffic flows to Azure

---

## GitOps Model

- Source of truth: GitHub
- Deployment: ArgoCD
- Strategy:
  - ApplicationSet
  - multi-cluster sync

---

## CI/CD Strategy

- GitHub Actions
- OIDC authentication (no secrets)
- Pipeline stages:
  - lint (TFLint)
  - security scan (Checkov)
  - plan (Terraform/Terragrunt)
  - cost estimation (Infracost)
  - apply (manual approval)

---

## Infrastructure as Code

- Tooling:
  - Terraform (modules)
  - Terragrunt (orchestration)

Structure:

- `/modules` → reusable infrastructure
- `/live` → environment orchestration

Principles:

- DRY
- decoupled modules
- explicit dependencies

---

## Networking

- Cross-cloud via public endpoints
- IP restrictions enforced
- HTTPS only

Trade-off:
- zero cost
- higher latency vs private networking

---

## Security Model

- OIDC federation (GitHub → AWS/Azure)
- No stored credentials
- AKS Managed Identity
- EKS IRSA
- Secrets via external providers

---

## Observability

- Prometheus (metrics)
- Fluent Bit (logs)
- Grafana or cloud dashboards
- Health endpoints:
  - /healthz
  - /readyz
  - /livez

---

## Cost Strategy

- Low-cost environment design
- Support for:
  - ephemeral environments
  - scheduled destroy

FinOps is part of architecture decisions.

---

## Key Trade-offs

| Area       | Decision         | Trade-off                  |
| ---------- | ---------------- | -------------------------- |
| Failover   | Active-Passive   | downtime during switch     |
| Data       | Single DB        | cross-cloud latency        |
| Networking | Public endpoints | higher latency             |
| CI/CD      | OIDC             | initial complexity         |

---

## Operational Philosophy

- Prefer simplicity over theoretical perfection
- Design for failure, not for ideal conditions
- Automate recovery wherever possible

---

## Anti-Patterns

- No multi-cloud without clear purpose
- No active-active without data strategy
- No hardcoded secrets
- No tight coupling between modules

---

## End Goal

This platform must demonstrate:

- real-world resilience patterns
- production-ready infrastructure design
- strong DevOps/SRE practices

It should answer: "Can this system survive failure without human intervention?"
