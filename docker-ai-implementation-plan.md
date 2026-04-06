# Docker Implementation Plan — AstaBot (PST BPS Banggai)

> **Tujuan dokumen ini**: Referensi lengkap semua perubahan Docker yang diterapkan pada repo ini.
> Jika repo upstream diupdate dan perubahan Docker hilang/konflik, lampirkan file ini
> ke AI assistant agar bisa menerapkan ulang perubahan dengan benar.

---

## Konteks

Repo ini (fork/clone dari repo orang lain) menjalankan **dua proses**:

1. **Node.js (`server-wpp.js`)** — Bot WhatsApp menggunakan WPPConnect (Puppeteer + Chromium headless)
2. **Python (`server.py`)** — Flask server + ChromaDB untuk RAG (Retrieval-Augmented Generation)

Node.js mengirim HTTP request ke Python server (`localhost:5000`) untuk mendapatkan prompt yang diperkaya konteks dokumen, lalu meneruskannya ke Gemini AI.

Semua perubahan Docker menggunakan pendekatan **single container** (satu container menjalankan kedua proses).

---

## Daftar Perubahan

### FILE BARU (5 file)

#### 1. `Dockerfile` — Multi-stage build

```dockerfile
# Stage 1: python-base (python:3.11-slim-bookworm)
#   - Install Python deps dari requirements.txt + python-dotenv
#   - Pre-download NLTK data (punkt, punkt_tab) agar tidak perlu internet saat runtime
#
# Stage 2: app (node:20-bookworm-slim)
#   - Install Chromium + dependensi sistem Puppeteer
#   - Install python3 + pip dari Debian packages
#   - Copy Python packages dari stage 1
#   - npm ci --omit=dev
#   - Copy source code
#   - ENV defaults: PORT_NODE=3000, PORT_PY=5000, PORT_WEB=80, BOT_NAME=ASTA, BOT_NUMBER=(kosong)
#   - EXPOSE 80 saja (3000 & 5000 internal only)
#   - Entrypoint: start.sh
```

Key decisions:
- `PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true` + `PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium` → gunakan Chromium sistem
- `BOT_NUMBER` default kosong → mode QR Code
- Hanya expose port 80 (pairing web), port 3000 & 5000 komunikasi internal saja

---

#### 2. `start.sh` — Entrypoint script

Fungsi:
1. Jalankan `python server.py` di background
2. Health check loop ke `http://localhost:${PORT_PY}/` sampai Python server ready (max 30 retry × 2 detik)
3. Jalankan `node server-wpp.js` di background
4. Trap `SIGTERM`/`SIGINT` → graceful shutdown kedua proses
5. `wait -n` → jika salah satu process mati, shutdown semua

---

#### 3. `pairing.html` — Halaman web untuk QR Code / Link Code

Halaman web sederhana (dark theme ala WhatsApp) yang:
- Terhubung ke SSE endpoint `/events` di port `PORT_WEB`
- Menampilkan **QR Code** (base64 image) atau **Link Code** (teks) secara real-time
- Auto-refresh saat kode baru digenerate
- Menampilkan "Sesi tersimpan ✓" saat sudah terhubung
- Auto-reconnect jika koneksi SSE terputus

Event SSE yang didukung:
- `qr` → data: base64 image QR code
- `linkcode` → data: string kode pairing
- `connected` → sesi berhasil tersambung

---

#### 4. `.dockerignore`

Exclude: `node_modules/`, `.git/`, `.gitignore`, `.env`, `tokens/`, `__pycache__/`, `*.pyc`, `*.pyo`, `*.md`, `flow.txt`, `.dockerignore`, `Dockerfile`

---

#### 5. `.gitignore`

Exclude: `node_modules/`, `__pycache__/`, `*.pyc`, `.env`, `tokens/`, `.DS_Store`, `Thumbs.db`, `.vscode/`, `.idea/`, `venv/`

---

### FILE DIMODIFIKASI (3 file)

#### 6. `server-wpp.js` — Perubahan utama

**Tambahan import:**
```javascript
import http from "http";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
```

**Tambahan: Pairing Web Server (SSE)**
Ditambahkan sebelum blok `wppconnect.create()`:
```javascript
const PORT_WEB = process.env.PORT_WEB || 80;
const sseClients = [];

function broadcastSSE(event, data) { /* kirim ke semua SSE clients */ }

const webServer = http.createServer((req, res) => {
  // GET / → serve pairing.html
  // GET /events → SSE endpoint
});

webServer.listen(PORT_WEB);
```

**Perubahan: WPPConnect config — dual auth mode**

SEBELUM (upstream):
```javascript
wppconnect.create({
    session: BOT_NAME,
    phoneNumber: BOT_NUMBER,           // ← selalu pakai link code
    catchLinkCode: (str) => {
        console.error("Code: " + str); // ← hanya print ke console
    },
    ...
})
```

SESUDAH:
```javascript
const useLinkCode = BOT_NUMBER && BOT_NUMBER.trim() !== "";
const wppConfig = { session: BOT_NAME, ... };

if (useLinkCode) {
    wppConfig.phoneNumber = BOT_NUMBER;
    wppConfig.catchLinkCode = (code) => {
        broadcastSSE("linkcode", code);   // ← broadcast ke web
    };
} else {
    wppConfig.catchQR = (base64Qr, asciiQR, attempts) => {
        broadcastSSE("qr", base64Qr);     // ← broadcast QR ke web
    };
}

wppconnect.create(wppConfig).then((client) => {
    broadcastSSE("connected", "true");    // ← notify web: sesi tersimpan
    start(client);
});
```

**Logika bisnis (fungsi `start()`, `handleSessionExpiration()`, `checkSessionExpiration()`, `sendWhatsAppMessage()`, `markMessageAsSeen()`)**: TIDAK DIUBAH.

---

#### 7. `aiHandlers.js` — Fix URL Python server

SEBELUM (upstream):
```javascript
const response = await axios.post('your-py-url/get_prompt', {
```

SESUDAH:
```javascript
const PORT_PY = process.env.PORT_PY || 5000;
const response = await axios.post(`http://localhost:${PORT_PY}/get_prompt`, {
```

Alasan: URL asli `'your-py-url'` adalah placeholder yang tidak bisa berfungsi. Karena kedua proses jalan dalam satu container, gunakan `localhost`.

---

#### 8. `server.py` — Fix port + health check

SEBELUM (upstream):
```python
# Tidak ada health check endpoint

if __name__ == "__main__":
    host = '0.0.0.0'
    port = os.getenv('PORT_PY')         # port tidak dipakai di app.run()
    app.run(host=host, debug=True)      # selalu debug=True, port default Flask
    print("Python Server Runnig on Port : ", port)  # tidak pernah tercetak (setelah app.run blocking)
```

SESUDAH:
```python
@app.route("/", methods=["GET"])
def health_check():
    return jsonify({"status": "ok"}), 200   # untuk start.sh readiness check

if __name__ == "__main__":
    host = '0.0.0.0'
    port = int(os.getenv('PORT_PY', 5000))  # default 5000, cast ke int
    print(f"Python Server Starting on Port: {port}")
    app.run(host=host, port=port, debug=False)
```

Fix 3 bug:
1. `port` tidak di-pass ke `app.run()` → Flask selalu pakai port default
2. `print()` setelah `app.run()` tidak pernah tereksekusi (blocking)
3. `debug=True` di production → security risk

---

#### 9. `.env` — Update defaults

SEBELUM:
```env
BOT_NUMBER=6282151067916
```

SESUDAH:
```env
# Kosongkan untuk mode QR Code (default), isi untuk mode Link Code
BOT_NUMBER=

# === Konfigurasi Web Pairing ===
PORT_WEB=80
```

---

## Environment Variables Lengkap

| Variable | Deskripsi | Default | Wajib |
|---|---|---|---|
| `GEMINI_API_KEY` | API key Google Gemini AI | — | ✅ |
| `PEGAWAI_NUMBER` | Nomor pegawai, JSON array string | — | ✅ |
| `BOT_NAME` | Nama sesi WPPConnect | `ASTA` | |
| `BOT_NUMBER` | Nomor WA. Kosong=QR, isi=Link Code | _(kosong)_ | |
| `PORT_WEB` | Port halaman pairing web | `80` | |
| `PORT_NODE` | Port internal Node.js | `3000` | |
| `PORT_PY` | Port internal Python Flask | `5000` | |

---

## Arsitektur

```
┌─────────────────────────────────────────────┐
│              Docker Container               │
│                                             │
│  start.sh (entrypoint)                      │
│    ├── python server.py    (port 5000)      │
│    └── node server-wpp.js  (port 3000)      │
│              │                              │
│              ├── WPPConnect (Puppeteer)      │
│              │     catchQR / catchLinkCode   │
│              │          │                   │
│              └── HTTP Server (port 80)──────────── EXPOSE 80
│                    ├── GET /  → pairing.html │
│                    └── GET /events → SSE     │
└─────────────────────────────────────────────┘
```

---

## Catatan untuk Re-apply

Jika repo upstream diupdate:

1. **File baru** (`Dockerfile`, `start.sh`, `pairing.html`, `.dockerignore`, `.gitignore`) → kemungkinan besar tidak terdampak, cukup pastikan masih ada
2. **`server-wpp.js`** → paling rawan konflik. Perhatikan:
   - Import tambahan (`http`, `fs`, `path`, `fileURLToPath`)
   - Blok pairing web server (SSE) ditambahkan sebelum `wppconnect.create()`
   - `wppconnect.create()` diubah dari hardcoded config → dynamic config berdasarkan `BOT_NUMBER`
   - Fungsi `broadcastSSE("connected", "true")` di `.then(client)`
   - **Logika bisnis tidak diubah** — fungsi `start()` dan seterusnya tetap sama
3. **`aiHandlers.js`** → cek apakah `'your-py-url'` masih ada atau sudah diubah upstream
4. **`server.py`** → cek health check endpoint `/` dan apakah `port` sudah dipakai di `app.run()`
5. **`.env`** → pastikan `BOT_NUMBER` kosong dan `PORT_WEB` ada
