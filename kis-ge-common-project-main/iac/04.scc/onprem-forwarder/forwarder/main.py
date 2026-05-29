"""SCC findings → on-prem HTTPS forwarder.

Cloud Run Job ENTRYPOINT. 한 번 실행 후 종료.
Cloud Scheduler가 cron으로 :run API 호출 → 이 컨테이너 실행.

흐름:
  1) ORG_ID/SOURCES/-/findings 호출 (filter = SCC_FILTER AND event_time > now-LOOKBACK)
  2) 페이지네이션으로 전부 수집
  3) JSON 배열로 묶어 ONPREM_ENDPOINT에 POST (chunked)
  4) 성공이면 exit 0, 부분 실패면 exit non-zero (Scheduler가 다음 주기 재시도)

Direct VPC egress + Cloud NAT 덕분에 모든 외부 호출이 NAT 고정 IP를 통해 SNAT됨.
"""

import json
import logging
import os
import sys
import time
from datetime import datetime, timedelta, timezone

import requests
from google.cloud import securitycenter_v2

# ────────────────────────────────────────────────────────────────────
# Config
# ────────────────────────────────────────────────────────────────────
ORG_ID = os.environ.get("ORG_ID", "").strip()
SCC_FILTER = os.environ.get("SCC_FILTER", 'state="ACTIVE"').strip()
ONPREM_ENDPOINT = os.environ.get("ONPREM_ENDPOINT", "").strip()
LOOKBACK_MINUTES = int(os.environ.get("LOOKBACK_MINUTES", "75"))

# 옵션 — 앱 자체로는 인증 안 함. 필요 시 Secret Manager에서 주입.
ONPREM_AUTH_HEADER = os.environ.get("ONPREM_AUTH_HEADER", "").strip()  # 예: "Bearer xxx"

# 1 finding당 1 POST. on-prem 수신 측이 단건 처리 가정 — 늘리려면 ENV로 override.
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "1"))

# HTTPS 타임아웃 / 재시도
HTTP_TIMEOUT_SEC = int(os.environ.get("HTTP_TIMEOUT_SEC", "30"))
HTTP_RETRIES = int(os.environ.get("HTTP_RETRIES", "3"))

# ────────────────────────────────────────────────────────────────────
# Logging — Cloud Run Logs로 JSON 구조화 출력
# ────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='{"ts":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}',
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
log = logging.getLogger("scc-forwarder")


def fail(msg: str, exit_code: int = 1) -> None:
    log.error(msg)
    sys.exit(exit_code)


def validate_env() -> None:
    if not ORG_ID:
        fail("ORG_ID 미설정")
    if not ONPREM_ENDPOINT:
        fail("ONPREM_ENDPOINT 미설정 — terraform var.scc_forwarder_onprem_endpoint 채울 것")
    if not ONPREM_ENDPOINT.startswith("https://"):
        fail(f"ONPREM_ENDPOINT는 HTTPS여야 함: {ONPREM_ENDPOINT}")


def build_filter() -> str:
    """LOOKBACK_MINUTES 윈도우를 SCC_FILTER에 AND로 결합."""
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=LOOKBACK_MINUTES)
    # SCC filter syntax: event_time > "2025-01-01T00:00:00Z"
    cutoff_str = cutoff.strftime("%Y-%m-%dT%H:%M:%SZ")
    base = f'event_time > "{cutoff_str}"'
    if SCC_FILTER:
        return f"({SCC_FILTER}) AND {base}"
    return base


def fetch_findings() -> list[dict]:
    """SCC v2 API에서 findings 조회 + 직렬화 가능한 dict로 변환."""
    client = securitycenter_v2.SecurityCenterClient()
    parent = f"organizations/{ORG_ID}/sources/-"
    full_filter = build_filter()
    log.info(f"SCC list_findings parent={parent} filter={full_filter}")

    req = securitycenter_v2.ListFindingsRequest(
        parent=parent,
        filter=full_filter,
        page_size=1000,
    )

    results: list[dict] = []
    try:
        for item in client.list_findings(request=req):
            f = item.finding
            results.append(
                {
                    "name": f.name,
                    "parent": f.parent,
                    "resource_name": f.resource_name,
                    "state": f.state.name if hasattr(f.state, "name") else str(f.state),
                    "category": f.category,
                    "severity": (
                        f.severity.name if hasattr(f.severity, "name") else str(f.severity)
                    ),
                    "event_time": f.event_time.isoformat() if f.event_time else None,
                    "create_time": (
                        f.create_time.isoformat() if f.create_time else None
                    ),
                    "description": f.description,
                    "external_uri": f.external_uri,
                    "finding_class": (
                        f.finding_class.name
                        if hasattr(f.finding_class, "name")
                        else str(f.finding_class)
                    ),
                    "source_properties": dict(f.source_properties)
                    if f.source_properties
                    else {},
                }
            )
    except Exception as e:
        fail(f"SCC API 조회 실패: {type(e).__name__}: {e}")

    log.info(f"SCC findings 수집: {len(results)}건")
    return results


def chunks(seq: list, n: int):
    for i in range(0, len(seq), n):
        yield seq[i : i + n]


def post_batch(batch: list[dict]) -> tuple[bool, str]:
    """단일 배치 POST. 성공/실패 + 에러 메시지 반환."""
    headers = {"Content-Type": "application/json"}
    if ONPREM_AUTH_HEADER:
        # ex: "Authorization: Bearer abc" → header "Authorization" : "Bearer abc"
        if ":" in ONPREM_AUTH_HEADER:
            k, _, v = ONPREM_AUTH_HEADER.partition(":")
            headers[k.strip()] = v.strip()
        else:
            headers["Authorization"] = ONPREM_AUTH_HEADER

    payload = {
        "org_id": ORG_ID,
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "count": len(batch),
        "findings": batch,
    }

    last_err = ""
    for attempt in range(1, HTTP_RETRIES + 1):
        try:
            resp = requests.post(
                ONPREM_ENDPOINT,
                json=payload,
                headers=headers,
                timeout=HTTP_TIMEOUT_SEC,
            )
            if 200 <= resp.status_code < 300:
                return True, f"HTTP {resp.status_code}"
            last_err = f"HTTP {resp.status_code}: {resp.text[:200]}"
            log.warning(f"on-prem 응답 비정상 (시도 {attempt}/{HTTP_RETRIES}): {last_err}")
        except requests.RequestException as e:
            last_err = f"{type(e).__name__}: {e}"
            log.warning(f"on-prem 호출 실패 (시도 {attempt}/{HTTP_RETRIES}): {last_err}")

        if attempt < HTTP_RETRIES:
            time.sleep(2**attempt)  # exponential backoff: 2s, 4s

    return False, last_err


def main() -> int:
    started = time.time()
    log.info(f"forwarder 시작 — org={ORG_ID} lookback={LOOKBACK_MINUTES}min")
    validate_env()

    findings = fetch_findings()
    if not findings:
        log.info("전송할 findings 없음 — 정상 종료")
        return 0

    total = len(findings)
    sent = 0
    failed_batches = 0
    for batch in chunks(findings, BATCH_SIZE):
        ok, info = post_batch(batch)
        if ok:
            sent += len(batch)
            log.info(f"batch 전송 성공: {len(batch)}건 ({info})")
        else:
            failed_batches += 1
            log.error(f"batch 전송 실패: {len(batch)}건 — {info}")

    elapsed = time.time() - started
    log.info(
        f"종료 — total={total} sent={sent} failed_batches={failed_batches} elapsed={elapsed:.1f}s"
    )

    return 0 if failed_batches == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
