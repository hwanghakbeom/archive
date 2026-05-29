"""SCC PubSub push → on-prem TCP forwarder.

Cloud Run Service (webhook). PubSub push subscription이 SCC finding 메시지를
HTTPS POST로 전달하면, 본 서비스가 메시지를 디코드해 raw TCP socket으로
on-prem(IP:port)에 line-delimited JSON으로 즉시 전송한다.

- PubSub message.data = SCC NotificationMessage (finding + resource JSON), base64
- TCP 전송: 메시지 1개당 socket 1회 open → JSON line + "\n" 전송 → close
- 성공: 204 응답 (PubSub ack)
- 실패: 5xx 응답 → PubSub가 retry_policy로 재시도 (10s..600s exp backoff)

ENV:
  ONPREM_HOST       (필수) on-prem 수신 IP/hostname
  ONPREM_PORT       (필수) on-prem 수신 TCP port
  TCP_TIMEOUT_SEC   (선택) TCP 연결/전송 timeout, default 10
"""

import base64
import json
import logging
import os
import socket
import sys

from flask import Flask, jsonify, request

ONPREM_HOST = os.environ.get("ONPREM_HOST", "").strip()
ONPREM_PORT = int(os.environ.get("ONPREM_PORT", "0") or 0)
TCP_TIMEOUT_SEC = int(os.environ.get("TCP_TIMEOUT_SEC", "10"))

logging.basicConfig(
    level=logging.INFO,
    format='{"ts":"%(asctime)s","level":"%(levelname)s","msg":%(message)s}',
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
log = logging.getLogger("scc-tcp-forwarder")

if not ONPREM_HOST or ONPREM_PORT <= 0:
    log.error('"ONPREM_HOST 또는 ONPREM_PORT 미설정/잘못된 값"')
    sys.exit(1)

app = Flask(__name__)


def send_tcp(payload_bytes: bytes) -> None:
    """raw TCP로 on-prem에 한 줄 전송 후 close."""
    with socket.create_connection((ONPREM_HOST, ONPREM_PORT), timeout=TCP_TIMEOUT_SEC) as sock:
        sock.sendall(payload_bytes)


@app.post("/")
def receive_pubsub():
    envelope = request.get_json(silent=True)
    if not envelope or "message" not in envelope:
        log.warning('"invalid pubsub envelope"')
        return jsonify({"error": "invalid pubsub envelope"}), 400

    message = envelope["message"]
    message_id = message.get("messageId") or message.get("message_id") or "?"
    publish_time = message.get("publishTime") or message.get("publish_time") or "?"

    data_b64 = message.get("data", "")
    try:
        finding_json_str = (
            base64.b64decode(data_b64).decode("utf-8") if data_b64 else "{}"
        )
    except Exception as e:
        log.error(
            '"base64 decode failed message_id=%s: %s"' % (message_id, e)
        )
        # 디코드 실패는 영구 에러 — PubSub retry 의미 없으니 200으로 drop.
        return "", 204

    # JSON 정합성 가벼운 검증 (실패해도 raw로 전송)
    try:
        json.loads(finding_json_str)
    except Exception:
        log.warning(
            '"finding not valid JSON — raw 전송 message_id=%s"' % message_id
        )

    payload = (finding_json_str.strip() + "\n").encode("utf-8")

    try:
        send_tcp(payload)
        log.info(
            '"forwarded message_id=%s publish_time=%s size=%d to %s:%d"'
            % (message_id, publish_time, len(payload), ONPREM_HOST, ONPREM_PORT)
        )
        return "", 204
    except socket.timeout:
        log.error(
            '"TCP timeout to %s:%d message_id=%s"'
            % (ONPREM_HOST, ONPREM_PORT, message_id)
        )
        return jsonify({"error": "tcp timeout"}), 503
    except (ConnectionRefusedError, OSError) as e:
        log.error(
            '"TCP send failed message_id=%s: %s"' % (message_id, e)
        )
        return jsonify({"error": "tcp failed"}), 503
    except Exception as e:
        log.error(
            '"unexpected error message_id=%s: %s"' % (message_id, e)
        )
        return jsonify({"error": "internal"}), 500


@app.get("/healthz")
def healthz():
    return "ok", 200


if __name__ == "__main__":
    # 로컬 디버깅용 (Cloud Run에선 gunicorn이 entrypoint).
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
