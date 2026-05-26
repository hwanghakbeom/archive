terraform {
  backend "gcs" {
    # Set via -backend-config in CI (Cloud Build runs in kis-gemini-common-prod):
    #   bucket = "kis-gemini-common-prod-tfstate"
    #   prefix = "lzone/org"
  }
}
