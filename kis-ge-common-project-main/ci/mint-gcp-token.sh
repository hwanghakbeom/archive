#!/usr/bin/env bash
# SA 키(env: kis_gemini_common_prod_iac_key)로 GCP access token을 발급해 stdout에 출력.
# provider의 느린 userinfo(www.googleapis.com) 호출을 우회하기 위해, terraform이
# GOOGLE_OAUTH_ACCESS_TOKEN을 직접 쓰도록 하는 용도.
# oauth2.googleapis.com/token (allowlist) 만 호출.
set -euo pipefail

printf '%s' "${kis_gemini_common_prod_iac_key:-}" > /tmp/sa.json

JWT=$(python3 -c 'import json,time,base64,subprocess; sa=json.load(open("/tmp/sa.json")); b=lambda d: base64.urlsafe_b64encode(d).rstrip(b"="); now=int(time.time()); hdr=b(json.dumps({"alg":"RS256","typ":"JWT"}).encode()); pl=b(json.dumps({"iss":sa["client_email"],"scope":"https://www.googleapis.com/auth/cloud-platform","aud":sa["token_uri"],"iat":now,"exp":now+3600}).encode()); si=hdr+b"."+pl; open("/tmp/k.pem","w").write(sa["private_key"]); sig=subprocess.run(["openssl","dgst","-sha256","-sign","/tmp/k.pem"],input=si,capture_output=True).stdout; print((si+b"."+b(sig)).decode())')

curl -s --max-time 20 -X POST https://oauth2.googleapis.com/token \
  -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${JWT}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))"
