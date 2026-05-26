terraform {
  backend "gcs" {
    # Set via -backend-config in CI (Cloud Build runs in kis-gemini-common):
    #   bucket = "kis-gemini-common-tfstate"
    #   prefix = "lzone/org"
  }
}
