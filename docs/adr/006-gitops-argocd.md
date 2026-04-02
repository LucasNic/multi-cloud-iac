# ADR-006: GitOps with ArgoCD for Multi-Cluster Deployment

## Status
Accepted (unchanged from original — tool-agnostic decision)

## Context

Two independent Kubernetes clusters (OKE + GKE) must run the same application
version at all times. The failover cluster is useless if it's running a different version.

## Decision

**ArgoCD with ApplicationSet** (cluster generator pattern). Git is the single source of truth.

### Pattern

```
Git repo (source of truth)
  └── k8s/
      ├── base/          → shared manifests
      ├── overlays/oci/  → OKE patches (Workload Identity, OCI ingress)
      └── overlays/gcp/  → GKE patches (Workload Identity, GCE ingress)

ArgoCD ApplicationSet → watches Git → deploys to both clusters
```

### Why ArgoCD (not Flux, not Helm-only)

- **ApplicationSet**: single manifest deploys to N clusters with per-cluster patches
- **Sync status dashboard**: visual confirmation both clusters are in sync
- **Self-heal**: detects and reverts manual `kubectl` changes
- **Multi-cluster native**: first-class support for N cluster targets

## Trade-offs

- (+) Git is the single source of truth for both clusters
- (+) ArgoCD surfaces sync drift before it becomes a failover problem
- (+) Kustomize overlays handle cloud-specific differences cleanly
- (-) ArgoCD itself needs to be bootstrapped on both clusters
- (-) Adds operational overhead (one more system to manage)
