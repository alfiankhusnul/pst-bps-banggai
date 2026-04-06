#!/bin/bash
set -e

echo "========================================="
echo "  PST BPS Banggai - Starting Services"
echo "========================================="

# ---- Start Python server in the background ----
echo "[START] Launching Python server on port ${PORT_PY:-5000}..."
python server.py &
PYTHON_PID=$!

# ---- Wait for Python server to be ready ----
MAX_RETRIES=30
RETRY_COUNT=0

echo "[START] Waiting for Python server to be ready..."
until curl -sf "http://localhost:${PORT_PY:-5000}/" > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "[ERROR] Python server failed to start after ${MAX_RETRIES} attempts."
        kill $PYTHON_PID 2>/dev/null || true
        exit 1
    fi
    echo "[START] Waiting for Python server... (attempt ${RETRY_COUNT}/${MAX_RETRIES})"
    sleep 2
done

echo "[START] Python server is ready!"

# ---- Start Node.js server in the foreground ----
echo "[START] Membersihkan sisa lock Profile Chromium sebelumnya..."
# Hapus symlink SingletonLock dan SingletonCookie yang tertinggal di folder tokens
find tokens/ -name "SingletonLock" -type l -delete 2>/dev/null || true
find tokens/ -name "SingletonCookie" -type l -delete 2>/dev/null || true

echo "[START] Launching Node.js server on port ${PORT_NODE:-3000}..."
node server-wpp.js &
NODE_PID=$!

# ---- Graceful shutdown handler ----
cleanup() {
    echo ""
    echo "[STOP] Shutting down services..."
    kill $NODE_PID 2>/dev/null || true
    kill $PYTHON_PID 2>/dev/null || true
    wait $NODE_PID 2>/dev/null || true
    wait $PYTHON_PID 2>/dev/null || true
    echo "[STOP] All services stopped."
    exit 0
}

trap cleanup SIGTERM SIGINT

# ---- Wait for either process to exit ----
wait -n $PYTHON_PID $NODE_PID
EXIT_CODE=$?

echo "[ERROR] One of the services exited with code ${EXIT_CODE}. Shutting down..."
cleanup
