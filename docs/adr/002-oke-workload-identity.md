# ADR-002: OKE Workload Identity for Pod-Level Access to OCI Services

## Status
Accepted

## Context

Replaces ADR-002 (AKS System-Assigned Managed Identity), which was specific to Azure.

OCI pods running on OKE need to access OCI services (Object Storage, Vault) without
storing credentials in the cluster. OCI provides two mechanisms:
1. Instance Principal — identity bound to the VM node (node-level, not pod-level)
2. Workload Identity — identity bound to a Kubernetes ServiceAccount (pod-level)

## Decision

Use **OCI Workload Identity** bound to Kubernetes ServiceAccounts.

### How It Works

1. OKE cluster has an OIDC issuer URL
2. A dynamic group is created in OCI IAM matching the ServiceAccount
3. Policies grant the dynamic group specific OCI permissions
4. Pods annotate their ServiceAccount → OCI SDK picks up the token automatically

### Why Not Instance Principal

- Instance Principal grants permissions to the entire node, not individual pods
- Any pod on the node inherits the permissions — violates least privilege
- Workload Identity is the OCI equivalent of EKS IRSA and AKS Workload Identity

## Implementation

```hcl
# OKE cluster must have OIDC enabled
oidc_discovery_enabled = true

# ServiceAccount annotation
kubernetes.io/serviceaccount: my-app
```

OCI IAM dynamic group:
```
ALL {resource.type = 'workloadidentity', resource.namespace = 'default'}
```

## Trade-offs

- (+) Pod-level identity, follows least privilege
- (+) No secrets to rotate or store
- (+) OCI destroys the identity when the cluster is deleted
- (-) Requires OCI IAM policy configuration (one-time bootstrap)
- (-) Less documentation than AWS IRSA or Azure Workload Identity
