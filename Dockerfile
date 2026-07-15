# Build frontend
FROM node:22-alpine AS frontend-build
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# Runtime
FROM python:3.12-slim
WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/ ./backend/
COPY --from=frontend-build /app/frontend/dist ./frontend/dist

ENV FORGE_DATA_DIR=/data

RUN useradd -m -u 1000 forge \
    && mkdir -p /data \
    && chown forge:forge /data
USER forge

VOLUME ["/data"]
EXPOSE 8081

CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8081"]
