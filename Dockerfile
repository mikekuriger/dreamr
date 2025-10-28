# Dockerfile
ARG PYTHON_VERSION=3.11
FROM python:${PYTHON_VERSION}-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

# System deps for Pillow, mysqlclient, and SSL/OAuth bits
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc pkg-config curl \
    libjpeg62-turbo-dev zlib1g-dev libpng-dev \
    default-libmysqlclient-dev libssl-dev libffi-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps first for better layer caching
COPY requirements.txt ./
# Ensure gunicorn is present even if not listed
RUN pip install --no-cache-dir -r requirements.txt gunicorn

# Copy the app code
COPY . /app

# Optional: non-root
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

# If your app writes images/files, keep them under /data and mount it
VOLUME ["/data"]

EXPOSE 8000

# Simple healthcheck; change path if you have /health
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -fsS http://127.0.0.1:${PORT}/ || exit 1

# Gunicorn; adjust workers/threads/timeouts to your box
CMD ["gunicorn", "-w", "4", "-k", "gthread", "--threads", "8", "--timeout", "120", "-b", "0.0.0.0:8000", "app:app"]
