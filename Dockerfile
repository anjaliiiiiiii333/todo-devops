# --- Base image: small, official, Python 3.12 ---
FROM python:3.12-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DB_PATH=/app/data/todos.db

# Install dependencies first (better Docker layer caching:
# this layer only rebuilds when requirements.txt changes)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Now copy the actual application code
COPY . .

# Directory for the SQLite database (mounted as a volume so data survives restarts)
RUN mkdir -p /app/data

EXPOSE 5000

# Docker (and later ECS/EC2) use this to know if the container is actually healthy
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

# gunicorn = production-grade WSGI server (never use Flask's dev server in prod)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
