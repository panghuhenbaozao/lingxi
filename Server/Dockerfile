FROM python:3.12-slim

LABEL org.opencontainers.image.title="Lingxi IME Cloud Server (Self-Hosted Vaultwarden Mode)"
LABEL org.opencontainers.image.description="Zero-Knowledge E2EE LWW Sync, 6-Digit Cross-Device Clipboard Relay (SSE), Typing Habit Analytics & Web Console"
LABEL org.opencontainers.image.licenses="MIT"

WORKDIR /app/Server

COPY schema.sql lingxi_server.py dashboard.html /app/Server/

VOLUME ["/data"]

EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8787/api/v1/health', timeout=3)" || exit 1

CMD ["python3", "/app/Server/lingxi_server.py", "--host", "0.0.0.0", "--port", "8787", "--db", "/data/lingxi_cloud.sqlite3"]
