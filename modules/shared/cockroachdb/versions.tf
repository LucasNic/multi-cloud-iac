terraform {
  required_version = ">= 1.5"

  required_providers {
    cockroach = {
      source  = "cockroachdb/cockroach"
      version = "~> 1.0"
    }
  }
}
