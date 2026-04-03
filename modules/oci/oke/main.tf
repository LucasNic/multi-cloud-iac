###############################################################################
# OCI OKE — PRIMARY Cluster (Active in Active-Passive Failover)
#
# This cluster is the primary. All production traffic routes here by default.
# GKE (GCP) acts as PASSIVE failover, receiving traffic only when Cloudflare
# Workers detect OKE degradation via health checks.
#
# Compute: ARM A1 Flex — 4 OCPU + 24GB RAM, always free on OCI.
# Identity: OCI Workload Identity (pod-level, equivalent to EKS IRSA).
#
# Free tier resources used:
# - OKE control plane: always free
# - ARM A1 Flex instances: 4 OCPU + 24GB RAM total, always free
# - VCN + subnets: always free
###############################################################################


# --- VCN (Virtual Cloud Network) ---

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  display_name   = "${var.project_prefix}-${var.environment}-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = replace("${var.project_prefix}${var.environment}", "-", "")

  freeform_tags = local.common_tags
}

resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_prefix}-${var.environment}-igw"
  enabled        = true

  freeform_tags = local.common_tags
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_prefix}-${var.environment}-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.main.id
  }

  freeform_tags = local.common_tags
}

# --- Subnet: OKE nodes (public for free tier — no NAT gateway cost) ---

resource "oci_core_subnet" "nodes" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.main.id
  display_name      = "${var.project_prefix}-${var.environment}-nodes"
  cidr_block        = "10.0.10.0/24"
  route_table_id    = oci_core_route_table.public.id
  dns_label         = "nodes"

  freeform_tags = local.common_tags
}

# --- Subnet: Load Balancer (public) ---

resource "oci_core_subnet" "lb" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.main.id
  display_name      = "${var.project_prefix}-${var.environment}-lb"
  cidr_block        = "10.0.20.0/24"
  route_table_id    = oci_core_route_table.public.id
  dns_label         = "lb"

  freeform_tags = local.common_tags
}

# --- Security List: allow HTTPS inbound to LB ---

resource "oci_core_security_list" "lb" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_prefix}-${var.environment}-lb-sl"

  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "HTTPS inbound (Cloudflare proxied)"

    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    description = "HTTP inbound (redirect to HTTPS)"

    tcp_options {
      min = 80
      max = 80
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "All outbound"
  }

  freeform_tags = local.common_tags
}

# --- OKE Cluster ---

resource "oci_containerengine_cluster" "main" {
  compartment_id     = var.compartment_id
  name               = "${var.project_prefix}-${var.environment}-oke"
  kubernetes_version = var.kubernetes_version
  vcn_id             = oci_core_vcn.main.id

  cluster_pod_network_options {
    cni_type = "OCI_VCN_IP_NATIVE"
  }

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.lb.id
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.lb.id]

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }

    admission_controller_options {
      is_pod_security_policy_enabled = false
    }
  }

  freeform_tags = local.common_tags
}

# --- Node Pool: ARM A1 Flex (OCI Always Free) ---
#
# ARM A1 Flex free tier: 4 OCPU + 24GB RAM total per tenancy.
# We use 1 node with 4 OCPU + 24GB to maximize available resources.
# Shape: VM.Standard.A1.Flex

resource "oci_containerengine_node_pool" "main" {
  compartment_id     = var.compartment_id
  cluster_id         = oci_containerengine_cluster.main.id
  name               = "${var.project_prefix}-${var.environment}-arm-pool"
  kubernetes_version = var.kubernetes_version

  node_shape = "VM.Standard.A1.Flex"

  node_shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gb
  }

  node_source_details {
    image_id    = var.node_image_id
    source_type = "IMAGE"

    boot_volume_size_in_gbs = 50
  }

  node_config_details {
    size = var.node_count

    placement_configs {
      availability_domain = var.availability_domain
      subnet_id           = oci_core_subnet.nodes.id
    }

    node_pool_pod_network_option_details {
      cni_type          = "OCI_VCN_IP_NATIVE"
      pod_subnet_ids    = [oci_core_subnet.nodes.id]
      max_pods_per_node = 31
    }
  }

  node_metadata = {
    user_data = base64encode(templatefile("${path.module}/templates/cloud-init.sh.tpl", {
      project     = var.project_prefix
      environment = var.environment
    }))
  }

  freeform_tags = local.common_tags
}

# --- Locals ---

locals {
  common_tags = merge(
    {
      project     = var.project_prefix
      environment = var.environment
      managed_by  = "terraform"
      module      = "oke"
      role        = "primary-cluster"
    },
    var.extra_tags
  )
}

# --- Variables ---

variable "compartment_id" {
  description = "OCI compartment OCID"
  type        = string
}

variable "project_prefix" {
  type = string
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "kubernetes_version" {
  description = "Kubernetes version for OKE"
  type        = string
  default     = "v1.32.1"
}

variable "availability_domain" {
  description = "OCI availability domain name"
  type        = string
}

variable "node_image_id" {
  description = "OCI image OCID for ARM A1 nodes (Oracle Linux or Ubuntu ARM)"
  type        = string
}

variable "node_count" {
  description = "Number of ARM A1 nodes (free tier: 1 node with 4 OCPU / 24GB)"
  type        = number
  default     = 1
}

variable "node_ocpus" {
  description = "OCPUs per node (free tier total: 4)"
  type        = number
  default     = 4
}

variable "node_memory_gb" {
  description = "Memory in GB per node (free tier total: 24)"
  type        = number
  default     = 24
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}

# --- Outputs ---

output "cluster_id" {
  value = oci_containerengine_cluster.main.id
}

output "cluster_name" {
  value = oci_containerengine_cluster.main.name
}

output "cluster_endpoint" {
  value = split(":", oci_containerengine_cluster.main.endpoints[0].public_endpoint)[0]
}

output "oidc_discovery_endpoint" {
  description = "OIDC issuer URL for Workload Identity configuration"
  value       = "https://objectstorage.${var.region}.oraclecloud.com/n/${var.object_storage_namespace}/b/oidc/o/.well-known/openid-configuration"
}

output "vcn_id" {
  value = oci_core_vcn.main.id
}

output "node_subnet_id" {
  value = oci_core_subnet.nodes.id
}

output "lb_subnet_id" {
  value = oci_core_subnet.lb.id
}

variable "region" {
  description = "OCI region (e.g. sa-saopaulo-1)"
  type        = string
  default     = "sa-saopaulo-1"
}

variable "object_storage_namespace" {
  description = "OCI object storage namespace (tenancy name)"
  type        = string
}
