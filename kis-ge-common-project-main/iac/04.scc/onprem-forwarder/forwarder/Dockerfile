FROM python:3.12-slim

WORKDIR /app

# 시스템 deps — requests의 SSL 검증용 ca-certificates만 필요
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# Cloud Run Job은 ENTRYPOINT만 보고 한 번 실행 후 종료.
ENTRYPOINT ["python", "/app/main.py"]
