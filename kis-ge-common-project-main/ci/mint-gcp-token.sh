#!/usr/bin/env bash
# SA 키(env: kis_gemini_common_prod_iac_key)로 GCP access token을 발급해 stdout에 출력.
# provider의 느린 userinfo(www.googleapis.com) 호출을 우회하기 위해, terraform이
# GOOGLE_OAUTH_ACCESS_TOKEN을 직접 쓰도록 하는 용도. oauth2.googleapis.com/token만 호출.
set -euo pipefail

VAL="${kis_gemini_common_prod_iac_key:-}"
if [ -z "$VAL" ]; then
  echo "❌ SA 키 변수가 비어있음 — 파이프라인에 미주입 (Group/Protected/Env scope 확인)." >&2
  exit 1
fi
# File 타입 변수면 $VAL이 파일 경로, Variable 타입이면 JSON 내용.
if [ -f "$VAL" ]; then
  cp "$VAL" /tmp/sa.json
else
  printf '%s' "$VAL" > /tmp/sa.json
fi

# JWT 서명: cryptography 우선, 없으면 openssl fallback (이미지에 openssl 없을 수 있음).
JWT=$(python3 <<'PYEOF'
import json, time, base64
sa = json.load(open("/tmp/sa.json"))
b = lambda d: base64.urlsafe_b64encode(d).rstrip(b"=")
now = int(time.time())
hdr = b(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
pl = b(json.dumps({
    "iss": sa["client_email"],
    "scope": "https://www.googleapis.com/auth/cloud-platform",
    "aud": sa["token_uri"],
    "iat": now, "exp": now + 3600,
}).encode())
si = hdr + b"." + pl
try:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding
    key = serialization.load_pem_private_key(sa["private_key"].encode(), password=None)
    sig = key.sign(si, padding.PKCS1v15(), hashes.SHA256())
except Exception:
    import subprocess
    open("/tmp/k.pem", "w").write(sa["private_key"])
    sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", "/tmp/k.pem"],
                         input=si, capture_output=True).stdout
print((si + b"." + b(sig)).decode())
PYEOF
)

curl -s --max-time 20 -X POST https://oauth2.googleapis.com/token \
  -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${JWT}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))"
