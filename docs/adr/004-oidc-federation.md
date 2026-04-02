# ADR-004: OIDC Federation for CI/CD Authentication

## Status
Accepted

## Context

GitHub Actions needs to authenticate against OCI and GCP to run Terraform and
deploy workloads. Options:
1. **Stored credentials**: Access keys/service account keys stored as GitHub Secrets
2. **OIDC federation**: GitHub Actions presents a short-lived JWT, cloud validates it

## Decision

Use **OIDC federation** for all cloud authentication in GitHub Actions. Zero stored keys.

### Implementation per Cloud

**OCI**
- Create a dynamic group in OCI IAM for the GitHub Actions OIDC provider
- Create an identity provider in OCI IAM pointing to `token.actions.githubusercontent.com`
- Restrict to specific repo + branch via subject claim

**GCP**
- Create a Workload Identity Pool in GCP IAM
- Create a provider within the pool for GitHub Actions OIDC
- Bind a GCP Service Account to the pool with attribute conditions
- Restrict to specific repo + branch

### Subject Restriction

All OIDC configurations restrict to:
- `repo:lucasnicoloso/multi-cloud-portfolio:ref:refs/heads/main` (apply)
- `repo:lucasnicoloso/multi-cloud-portfolio:pull_request` (plan only)

### Bootstrap Problem

OIDC setup itself requires one-time local authentication (chicken-and-egg).
Documented in `bootstrap/README.md`.

## Trade-offs

- (+) Zero stored secrets — nothing to leak or rotate
- (+) Credentials scoped per-job, expire in 1 hour automatically
- (+) Auditable: cloud logs show exactly which workflow run authenticated
- (-) Bootstrap requires one-time local auth with elevated permissions
- (-) OCI OIDC setup is less documented than AWS/Azure equivalents
