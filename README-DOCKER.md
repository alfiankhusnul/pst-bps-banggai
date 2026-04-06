# 🐳 Docker — AstaBot (PST BPS Banggai)

Panduan menjalankan AstaBot menggunakan Docker. Image ini menjalankan **WhatsApp Bot (Node.js)** dan **RAG Server (Python)** dalam satu container.

---

## Daftar Isi

- [Prasyarat](#prasyarat)
- [Quick Start](#quick-start)
- [Environment Variables](#environment-variables)
- [Mode Autentikasi](#mode-autentikasi)
- [Halaman Pairing Web](#halaman-pairing-web)
- [Volume & Data Persist](#volume--data-persist)
- [Perintah Docker](#perintah-docker)
- [Troubleshooting](#troubleshooting)

---

## Prasyarat

- [Docker](https://docs.docker.com/get-docker/) terinstall di server/komputer
- API Key [Google Gemini AI](https://aistudio.google.com/app/apikey)

---

## Quick Start

### 1. Build image

```bash
docker build -t pst-bps-banggai .
```

### 2. Jalankan container

```bash
docker run -d \
  --name astabot \
  --restart unless-stopped \
  -e GEMINI_API_KEY=your_api_key_here \
  -e PEGAWAI_NUMBER='["6281234567890"]' \
  -v $(pwd)/tokens:/app/tokens \
  -p 8081:80 \
  pst-bps-banggai
```

### 3. Login WhatsApp

Buka **http://localhost:8081** di browser → scan QR Code dengan WhatsApp di HP → selesai!

---

## Environment Variables

| Variable | Deskripsi | Default | Wajib |
|---|---|---|---|
| `GEMINI_API_KEY` | API key Google Gemini AI | — | ✅ |
| `PEGAWAI_NUMBER` | Daftar nomor pegawai, format JSON array | — | ✅ |
| `BOT_NAME` | Nama sesi bot (nama tampilan) | `ASTA` | |
| `BOT_NUMBER` | Nomor WhatsApp bot. Kosong = QR Code, isi = Link Code | _(kosong)_ | |
| `PORT_WEB` | Port halaman pairing web (dalam container) | `80` | |
| `PORT_NODE` | Port internal Node.js | `3000` | |
| `PORT_PY` | Port internal Python Flask | `5000` | |

> ⚠️ **Jangan hardcode `GEMINI_API_KEY` di file apapun.** Selalu pass via `-e` atau `--env-file`.

### Menggunakan env file

Sebagai alternatif dari `-e`, buat file `docker.env`:

```env
GEMINI_API_KEY=your_api_key_here
PEGAWAI_NUMBER=["6281234567890"]
BOT_NAME=ASTA
```

Lalu jalankan:

```bash
docker run -d \
  --name astabot \
  --restart unless-stopped \
  --env-file docker.env \
  -v $(pwd)/tokens:/app/tokens \
  -p 8080:80 \
  pst-bps-banggai
```

---

## Mode Autentikasi

### QR Code (Default)

Digunakan ketika `BOT_NUMBER` **kosong** (default).

```bash
docker run -d --name astabot \
  -e GEMINI_API_KEY=your_key \
  -e PEGAWAI_NUMBER='["6281234567890"]' \
  -v $(pwd)/tokens:/app/tokens \
  -p 8081:80 \
  pst-bps-banggai
```

1. Buka `http://localhost:8081`
2. Buka WhatsApp di HP → **Setelan → Perangkat Tertaut → Tautkan Perangkat**
3. **Scan QR Code** yang tampil di halaman web
4. QR Code akan refresh otomatis jika kadaluarsa

### Link Code

Digunakan ketika `BOT_NUMBER` **diisi** dengan nomor WhatsApp (format internasional, tanpa `+`).

```bash
docker run -d --name astabot \
  -e BOT_NUMBER=6281234567890 \
  -e GEMINI_API_KEY=your_key \
  -e PEGAWAI_NUMBER='["6281234567890"]' \
  -v $(pwd)/tokens:/app/tokens \
  -p 8081:80 \
  pst-bps-banggai
```

1. Buka `http://localhost:8081`
2. Buka WhatsApp di HP → **Setelan → Perangkat Tertaut → Tautkan dengan nomor telepon**
3. **Masukkan kode** yang tampil di halaman web

---

## Halaman Pairing Web

Halaman web sederhana untuk menampilkan QR Code / Link Code secara real-time.

| Fitur | Keterangan |
|---|---|
| Auto-refresh | Kode baru otomatis ditampilkan tanpa reload halaman |
| Status connected | Menampilkan "Sesi tersimpan ✓" saat sudah terhubung |
| Auto-reconnect | Browser reconnect otomatis jika koneksi terputus |
| Dark theme | Tampilan gelap ala WhatsApp |

### Port Mapping

Port default dalam container adalah `80`. Mapping ke port host yang tersedia:

```bash
-p 8081:80     # akses di http://localhost:8081
-p 8080:80     # atau port lain jika 8081 sudah terpakai
-p 9090:80     # bebas port apapun
```

---

## Volume & Data Persist

### Sesi WhatsApp (`tokens/`)

```bash
-v $(pwd)/tokens:/app/tokens
```

Folder `tokens/` menyimpan data sesi WhatsApp. **Wajib di-mount** agar:
- Sesi tidak hilang saat container restart
- Tidak perlu scan QR Code ulang setiap kali restart

> Jika menggunakan path absolut di Windows:
> ```bash
> -v C:\path\to\tokens:/app/tokens
> ```

---

## Perintah Docker

### Melihat logs

```bash
docker logs -f astabot
```

### Restart container

```bash
docker restart astabot
```

### Stop container

```bash
docker stop astabot
```

### Hapus container

```bash
docker rm -f astabot
```

### Rebuild image (setelah update kode)

```bash
docker build --no-cache -t pst-bps-banggai .
docker rm -f astabot
docker run -d --name astabot \
  --restart unless-stopped \
  -e GEMINI_API_KEY=your_key \
  -e PEGAWAI_NUMBER='["6281234567890"]' \
  -v $(pwd)/tokens:/app/tokens \
  -p 8081:80 \
  pst-bps-banggai
```

---

## Troubleshooting

### QR Code tidak muncul di halaman web

- Pastikan container sudah running: `docker ps`
- Cek logs: `docker logs -f astabot`
- Pastikan port mapping benar: `-p 8081:80`

### Container crash / restart terus

```bash
docker logs astabot --tail 50
```

Kemungkinan penyebab:
- `GEMINI_API_KEY` tidak di-set atau salah
- `PEGAWAI_NUMBER` format salah (harus JSON array: `'["62xxx"]'`)
- Port konflik (ganti port host: `-p 9090:80`)

### Sesi WhatsApp hilang setelah restart

Pastikan volume `tokens/` di-mount:

```bash
-v $(pwd)/tokens:/app/tokens
```

### Chromium error di dalam container

Pastikan Docker memiliki cukup memory (minimal 512MB). Untuk membatasi:

```bash
docker run -d --name astabot --memory=1g ...
```

---

## Arsitektur Container

```
┌─────────────────────────────────────────────┐
│              Docker Container               │
│                                             │
│  ┌──────────────┐    ┌──────────────────┐   │
│  │  Python Flask │    │  Node.js WPP Bot │   │
│  │  port 5000   │◄───│  (Puppeteer +    │   │
│  │  RAG Server  │    │   Chromium)      │   │
│  └──────────────┘    └───────┬──────────┘   │
│        (internal)            │  (internal)   │
│                     ┌────────▼─────────┐    │
│                     │  Pairing Web     │    │
│                     │  port 80 ──────────── EXPOSE
│                     │  (QR / Link Code)│    │
│                     └──────────────────┘    │
└─────────────────────────────────────────────┘
```
