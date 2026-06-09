"""Model Armor 런타임 탐지 → SCC findings 브리지 (Cloud Function gen2).

흐름: 자회사 Model Armor SanitizeOperation 로그(MATCH_FOUND)
   → 자회사별 로그 싱크 → 중앙 Pub/Sub(ma-detections) → 이 함수
   → SCC findings.create (REST v2, 커스텀 Source)

scctest PoC(SCC - ARCHITECTURE.md) 검증 코드의 KIS 멀티자회사 버전:
  - finding resourceName을 로그 출처 자회사 프로젝트 번호로 매핑 (PROJECT_NUMBERS_JSON)
  - eventTime 미래값 clamp (SCC v2가 미래 timestamp를 INVALID_ARGUMENT로 거부)

SCC v2 CreateFinding 함정: body에 `name`(전체 경로) 필수, resourceName은 프로젝트 번호.

환경변수: SCC_ORG_ID, SCC_SOURCE_ID, FINDING_LOCATION(기본 global),
          PROJECT_NUMBERS_JSON({"kis-ge-prod":"692468...", ...}), DEFAULT_PROJECT_NUMBER
"""
import base64
import datetime
import hashlib
import json
import os

import functions_framework
import google.auth
import google.auth.transport.requests
import requests

ORG_ID = os.environ["SCC_ORG_ID"]
SOURCE_ID = os.environ["SCC_SOURCE_ID"]
LOCATION = os.environ.get("FINDING_LOCATION", "global")
PROJECT_NUMBERS = json.loads(os.environ.get("PROJECT_NUMBERS_JSON", "{}"))
DEFAULT_PROJECT_NUMBER = os.environ.get("DEFAULT_PROJECT_NUMBER", "")

_creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
_authreq = google.auth.transport.requests.Request()


def _token() -> str:
    if not _creds.valid:
        _creds.refresh(_authreq)
    return _creds.token


def _extract_matches(sanitization_result: dict) -> list:
    """탐지된 필터/infoType 요약 추출."""
    matches = []
    fr = sanitization_result.get("filterResults", {})
    sdp = fr.get("sdp", {}).get("sdpFilterResult", {}).get("inspectResult", {})
    if sdp.get("matchState") == "MATCH_FOUND":
        for f in sdp.get("findings", []):
            matches.append(f"SDP:{f.get('infoType', 'UNKNOWN')}")
    pijb = fr.get("pi_and_jailbreak", {}).get("piAndJailbreakFilterResult", {})
    if pijb.get("matchState") == "MATCH_FOUND":
        matches.append(f"PI_JAILBREAK:{pijb.get('confidenceLevel', '')}")
    mu = fr.get("malicious_uris", {}).get("maliciousUriFilterResult", {})
    if mu.get("matchState") == "MATCH_FOUND":
        matches.append("MALICIOUS_URI")
    rai = fr.get("rai", {}).get("raiFilterResult", {})
    if rai.get("matchState") == "MATCH_FOUND":
        for k, v in rai.get("raiFilterTypeResults", {}).items():
            if v.get("matchState") == "MATCH_FOUND":
                matches.append(f"RAI:{k}")
    return matches


def _clamp_event_time(ts: str) -> str:
    """eventTime이 미래면 now로 clamp (클럭 스큐 → INVALID_ARGUMENT 방지)."""
    now = datetime.datetime.now(datetime.timezone.utc)
    try:
        t = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
        if t > now:
            return now.isoformat().replace("+00:00", "Z")
        return ts
    except (ValueError, AttributeError):
        return now.isoformat().replace("+00:00", "Z")


@functions_framework.cloud_event
def handle(cloud_event):
    data = cloud_event.data.get("message", {}).get("data", "")
    if not data:
        return
    entry = json.loads(base64.b64decode(data).decode("utf-8"))

    payload = entry.get("jsonPayload", {})
    result = payload.get("sanitizationResult", {})
    if result.get("filterMatchState") != "MATCH_FOUND":
        return

    matches = _extract_matches(result)
    if not matches:
        return

    # 출처 자회사 프로젝트 → finding resourceName (프로젝트 번호 필수)
    # SanitizeOperation 로그 실측(2026-06-09): resource.labels에 project_id 없음.
    #   - logName = "projects/<id>/logs/..."          → project_id (표시용)
    #   - resource.labels.resource_container = "projects/<number>"  → 번호 (resourceName용, 직접)
    labels = entry.get("resource", {}).get("labels", {})
    log_name = entry.get("logName", "")
    parts = log_name.split("/")
    src_project_id = parts[1] if len(parts) > 1 and parts[0] == "projects" else ""
    rc = labels.get("resource_container", "")
    if rc.startswith("projects/"):
        project_number = rc.split("/")[-1]
    else:
        project_number = PROJECT_NUMBERS.get(src_project_id, DEFAULT_PROJECT_NUMBER)
    resource_name = f"//cloudresourcemanager.googleapis.com/projects/{project_number}"

    op = payload.get("operationType", "UNKNOWN")
    insert_id = entry.get("insertId", "")
    log_time = _clamp_event_time(entry.get("timestamp", ""))

    finding_id = "ma" + hashlib.sha1(insert_id.encode()).hexdigest()[:30]
    parent = f"organizations/{ORG_ID}/sources/{SOURCE_ID}/locations/{LOCATION}"

    body = {
        "name": f"{parent}/findings/{finding_id}",
        "state": "ACTIVE",
        "category": "MODEL_ARMOR_RUNTIME_DETECTION",
        "severity": "HIGH",
        "findingClass": "MISCONFIGURATION",
        "resourceName": resource_name,
        "eventTime": log_time,
        "sourceProperties": {
            "subsidiary_project": src_project_id,
            "operation_type": op,
            "matched_filters": ", ".join(matches),
            "log_insert_id": insert_id,
        },
    }
    url = f"https://securitycenter.googleapis.com/v2/{parent}/findings?findingId={finding_id}"
    resp = requests.post(
        url,
        headers={"Authorization": f"Bearer {_token()}", "Content-Type": "application/json"},
        data=json.dumps(body),
        timeout=30,
    )
    if resp.status_code == 200:
        print(f"finding created: {finding_id} | {src_project_id} | {matches}")
    else:
        print(f"finding create FAILED {resp.status_code}: {resp.text[:300]} | body={json.dumps(body)}")
        resp.raise_for_status()
