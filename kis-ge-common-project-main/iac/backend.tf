terraform {
  backend "gcs" {
    # Set via -backend-config in CI (Cloud Build runs in kis-common-gcp):
    #   bucket = "kis-common-gcp-tfstate"
    #   prefix = "lzone/org"
  }
}
