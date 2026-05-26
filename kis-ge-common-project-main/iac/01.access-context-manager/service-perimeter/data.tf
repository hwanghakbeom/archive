# 자회사 project ID → project number 변환.
# data.google_project는 enable_perimeter=true일 때만 활성화 (project 미존재 시 에러 회피).
data "google_project" "subsidiary" {
  for_each = var.enable_perimeter ? toset(var.subsidiary_project_ids) : toset([])

  project_id = each.value
}
