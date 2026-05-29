FROM python:3.12-slim

WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

ENV PORT=8080
EXPOSE 8080

# Cloud Run은 PORT env(default 8080)에 binding된 HTTP 서버를 expect.
# Service는 long-running이므로 gunicorn으로 worker/thread 운용.
CMD exec gunicorn --bind :${PORT} --workers 1 --threads 8 --timeout 30 main:app
