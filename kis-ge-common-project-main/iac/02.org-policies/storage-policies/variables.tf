variable "org_id" {
  description = "GCP 조직 ID."
  type        = string
}

variable "enforce_public_access_prevention" {
  description = "storage.publicAccessPrevention=enforced 조직 전체 강제 여부."
  type        = bool
  default     = true
}

variable "enforce_uniform_bucket_level_access" {
  description = "storage.uniformBucketLevelAccess=true 조직 전체 강제 여부."
  type        = bool
  default     = true
}
