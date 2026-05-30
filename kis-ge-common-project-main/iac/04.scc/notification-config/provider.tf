terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.20"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}
