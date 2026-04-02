# ADR-002: AKS System-Assigned Managed Identity over Service Principal

## Status
Accepted

## Decision
Use `identity { type = "SystemAssigned" }` for all AKS clusters.

> "We recommend using managed identities for AKS."
> — [Microsoft Docs](https://learn.microsoft.com/en-us/azure/aks/use-managed-identity)

### Why
- No client secret to rotate (90-day expiry eliminated)
- Identity destroyed with cluster (zero orphaned creds)
- Follows Azure Well-Architected Framework, Security Pillar
- Terraform: native azurerm, no azuread provider needed

### Role Assignments Required
- **Network Contributor** on VNet (LB/NSG management)
- **AcrPull** on ACR (image pulls via kubelet identity)
