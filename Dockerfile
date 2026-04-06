# ============================================================
# Stage 1: Python dependencies
# ============================================================
FROM python:3.11-slim-bookworm AS python-base

WORKDIR /tmp/python-build

COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt python-dotenv

# Pre-download NLTK data during build (so runtime doesn't need internet for this)
RUN python -c "import nltk; nltk.download('punkt', download_dir='/usr/local/nltk_data'); nltk.download('punkt_tab', download_dir='/usr/local/nltk_data')"

# ============================================================
# Stage 2: Final application image
# ============================================================
FROM node:20-bookworm-slim AS app

# ------- System dependencies for Chromium (Puppeteer/WPPConnect) -------
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    libnss3 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpangocairo-1.0-0 \
    libgtk-3-0 \
    libxshmfence1 \
    libx11-xcb1 \
    fonts-liberation \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    && rm -rf /var/lib/apt/lists/*

# ------- Copy Python packages from build stage -------
COPY --from=python-base /usr/local/lib/python3.11/site-packages /usr/lib/python3/dist-packages
COPY --from=python-base /usr/local/nltk_data /usr/local/nltk_data

# Symlink so `python` command works (Debian slim only ships `python3`)
RUN ln -sf /usr/bin/python3 /usr/bin/python

# Set NLTK data path
ENV NLTK_DATA=/usr/local/nltk_data

# ------- Puppeteer / Chromium config -------
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

# ------- Application setup -------
WORKDIR /app

# Copy package files first (better Docker layer caching)
COPY package.json package-lock.json ./

# Install Node.js dependencies (production only)
RUN npm ci --omit=dev

# Copy application source code
COPY . .

# ------- Default environment variables -------
ENV PORT_NODE=3000
ENV PORT_PY=5000
ENV PORT_WEB=8081
ENV BOT_NAME=ASTA
ENV BOT_NUMBER=

# ------- Expose ports -------
# Port 8081: Pairing web page (QR Code / Link Code)
# Port 3000 & 5000 tidak perlu di-expose (komunikasi internal dalam container)
EXPOSE 8081

# ------- Entrypoint -------
COPY start.sh /app/start.sh
# Convert Windows CRLF → LF (safeguard jika Git di Windows auto-convert line endings)
RUN sed -i 's/\r$//' /app/start.sh && chmod +x /app/start.sh

CMD ["/app/start.sh"]
