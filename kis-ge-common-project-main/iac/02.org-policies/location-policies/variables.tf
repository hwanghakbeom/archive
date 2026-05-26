variable "org_id" {
  description = "GCP 조직 ID."
  type        = string
}

variable "enable_resource_locations" {
  description = "gcp.resourceLocations 활성화. 신규 자원은 allowed_locations 안에만 생성 가능."
  type        = bool
  default     = true
}

variable "allowed_locations" {
  description = "허용 리전/멀티리전 목록 (LIST org policy 값 형식, in:<group> 또는 <location>)."
  type        = list(string)
  default = [
    "in:asia-northeast3-locations", # 서울 region 그룹
    "in:asia-locations",            # asia multi-region (DLP/Model Armor의 us 예외 위해 필요시 추가)
  ]
}
