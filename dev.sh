#!/usr/bin/env bash
# Local dev: backend on :8081 with reload, frontend on :5174 with HMR.
set -e
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
  python3 -m venv .venv
  ./.venv/bin/pip install -r requirements.txt
fi
if [ ! -d frontend/node_modules ]; then
  (cd frontend && npm install)
fi

FORGE_DATA_DIR=./data ./.venv/bin/python -m uvicorn backend.main:app --port 8081 --reload &
BACKEND_PID=$!
(cd frontend && npm run dev) &
FRONTEND_PID=$!
disown $BACKEND_PID $FRONTEND_PID
echo "Forge dev: backend http://localhost:8081  frontend http://localhost:5174"
wait
