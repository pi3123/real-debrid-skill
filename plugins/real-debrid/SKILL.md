---
name: real-debrid
description: "Full Real-Debrid API integration: add magnet links, poll torrent status, download files, unrestrict hoster links, check account/traffic info."
---

# Real-Debrid API Skill

Complete Real-Debrid API integration via `curl`. Covers torrents (magnet/torrent file), hoster link unrestrict, downloads, account info, and traffic monitoring.

## When to use

- User pastes a magnet link and wants to download it
- User pastes a hoster link (mega.nz, rapidgator, firedl, etc.) and wants a direct download
- User asks about their Real-Debrid account status, traffic, or downloads
- User says "rd", "real-debrid", or "unrestrict"

## Authentication

Token resolution (first match wins):

1. **Environment variable**: `RD_API_TOKEN`
2. **Config file**: `~/.rd/config` — a plain text file with `RD_API_TOKEN=<token>` on the first non-comment line

```bash
# Resolve token
if [ -n "${RD_API_TOKEN:-}" ]; then
  RD_TOKEN="$RD_API_TOKEN"
elif [ -f ~/.rd/config ]; then
  RD_TOKEN=$(grep -v '^#' ~/.rd/config | grep 'RD_API_TOKEN=' | head -1 | cut -d= -f2-)
fi
RD_TOKEN="${RD_TOKEN:?Set RD_API_TOKEN or create ~/.rd/config}"

BASE="https://api.real-debrid.com/rest/1.0"
```

All calls: `curl -sS -H "Authorization: Bearer $RD_TOKEN" "$BASE/..."`

**Rate limit**: 250 req/min. HTTP 429 = back off.

**Required tools**: `curl`, `jq`. Install missing: `sudo apt-get install -y curl jq`

---

## Workflow 1: Magnet Link → Download

The full lifecycle: add magnet → select files → poll until ready → download.

### Step 1: Add the magnet

```bash
TORRENT_ID=$(curl -sS -X POST \
  -H "Authorization: Bearer $RD_TOKEN" \
  -d "magnet=<MAGNET_LINK>" \
  "$BASE/torrents/addMagnet" | jq -r '.id')
```

Returns `{"id":"<id>","uri":"..."}`. Save the ID.

### Step 2: Check torrent info & select files

```bash
curl -sS -H "Authorization: Bearer $RD_TOKEN" \
  "$BASE/torrents/info/$TORRENT_ID" | jq .
```

Key fields: `status`, `files` (array of `{id, path, bytes, selected}`), `progress` (0–100), `speed`, `seeders`, `links`.

**Status flow**:

| Status | Agent action |
|---|---|
| `magnet_conversion` | Magnet resolving. Poll every 5s. |
| `waiting_files_selection` | **Must select files now** or torrent stalls. |
| `queued` | Waiting for slot. Poll every 10s. |
| `downloading` | In progress. Poll every 10–15s. Report progress/speed to user. |
| `downloaded` | Done! Proceed to Step 4. |
| `error` / `magnet_error` / `dead` | Failed. Report to user. |
| `virus` | Virus detected. Abort. |
| `compressing` / `uploading` | Finalizing. Poll every 10s. |

**Select files** (when status is `waiting_files_selection`):

```bash
# All files
curl -sS -X POST -H "Authorization: Bearer $RD_TOKEN" \
  -d "files=all" "$BASE/torrents/selectFiles/$TORRENT_ID"

# Specific file IDs (comma-separated, from /torrents/info files array)
curl -sS -X POST -H "Authorization: Bearer $RD_TOKEN" \
  -d "files=1,3,7" "$BASE/torrents/selectFiles/$TORRENT_ID"
```

**Selective download flow**: When a torrent has many files, show the file list with sizes, let the user pick, then select those IDs.

### Step 3: Poll until downloaded

Poll `/torrents/info/{id}` every 10–15s. Show progress: filename, %, speed, seeders.

When `status` == `"downloaded"`, `links[]` contains hoster URLs.

### Step 4: Unrestrict & download

Each link needs unrestricting for a direct URL:

```bash
LINKS=$(curl -sS -H "Authorization: Bearer $RD_TOKEN" \
  "$BASE/torrents/info/$TORRENT_ID" | jq -r '.links[]')

mkdir -p "$DOWNLOAD_DIR"
for LINK in $LINKS; do
  INFO=$(curl -sS -X POST -H "Authorization: Bearer $RD_TOKEN" \
    -d "link=$LINK" "$BASE/unrestrict/link")
  FILENAME=$(echo "$INFO" | jq -r '.filename')
  DIRECT=$(echo "$INFO" | jq -r '.download')
  FILESIZE=$(echo "$INFO" | jq -r '.filesize')

  echo "Downloading: $FILENAME ($(numfmt --to=iec $FILESIZE 2>/dev/null || echo "$FILESIZE bytes"))"
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 -C - \
    -o "$DOWNLOAD_DIR/$FILENAME" "$DIRECT"
done
```

### Step 5: Cleanup

```bash
curl -sS -X DELETE -H "Authorization: Bearer $RD_TOKEN" \
  "$BASE/torrents/delete/$TORRENT_ID"
```

Frees RD torrent slots. Download history is kept separately.

---

## Workflow 2: Hoster Link Unrestrict

For mega.nz, rapidgator, firedl, uploaded.net, etc.

### Check support

```bash
curl -sS -X POST -H "Authorization: Bearer $RD_TOKEN" \
  -d "link=<HOSTER_LINK>" "$BASE/unrestrict/check" | jq .
```

Returns `{filename, filesize, host, supported}`. If `supported` is 0, host unavailable.

### Unrestrict → direct link

```bash
RESULT=$(curl -sS -X POST -H "Authorization: Bearer $RD_TOKEN" \
  -d "link=<HOSTER_LINK>" "$BASE/unrestrict/link")
```

Response: `{id, filename, mimeType, filesize, link, host, chunks, download, streamable}`

### Unrestrict a folder

```bash
curl -sS -X POST -H "Authorization: Bearer $RD_TOKEN" \
  -d "link=<FOLDER_LINK>" "$BASE/unrestrict/folder" | jq .
```

Returns array of direct links.

### Download

```bash
FILENAME=$(echo "$RESULT" | jq -r '.filename')
DIRECT=$(echo "$RESULT" | jq -r '.download')
curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 -C - \
  -o "$DOWNLOAD_DIR/$FILENAME" "$DIRECT"
```

### With remote traffic (dedicated servers)

```bash
curl -sS -X POST -H "Authorization: Bearer $RD_TOKEN" \
  -d "link=<HOSTER_LINK>" -d "remote=1" \
  "$BASE/unrestrict/link" | jq .
```

Lifts account sharing protections.

---

## Workflow 3: Account & Traffic

### Account status

```bash
curl -sS -H "Authorization: Bearer $RD_TOKEN" "$BASE/user" | jq .
```

Fields: `type` ("premium"/"free"), `premium` (seconds left), `expiration`, `points`.

### Traffic usage (per-host breakdown)

```bash
curl -sS -H "Authorization: Bearer $RD_TOKEN" "$BASE/traffic" | jq .
```

Each host: `{left, bytes, links, limit, type, extra, reset}`.

### Traffic details by date range

```bash
curl -sS -H "Authorization: Bearer $RD_TOKEN" \
  "$BASE/traffic/details?start=YYYY-MM-DD&end=YYYY-MM-DD" | jq .
```

Max 31-day window.

### Convert fidelity points

```bash
curl -sS -X POST -H "Authorization: Bearer $RD_TOKEN" \
  "$BASE/settings/convertPoints"
```

### List recent downloads

```bash
curl -sS -H "Authorization: Bearer $RD_TOKEN" \
  "$BASE/downloads?limit=20" | jq .
```

### List active torrents

```bash
curl -sS -H "Authorization: Bearer $RD_TOKEN" \
  "$BASE/torrents?filter=active" | jq .
```

### Delete a download from history

```bash
curl -sS -X DELETE -H "Authorization: Bearer $RD_TOKEN" \
  "$BASE/downloads/delete/<ID>"
```

---

## Streaming (bonus)

Get transcoding links (HLS, DASH, MP4) for a file:

```bash
curl -sS -H "Authorization: Bearer $RD_TOKEN" \
  "$BASE/streaming/transcode/<FILE_ID>" | jq .
```

Get media info (codec, resolution, audio, subtitles):

```bash
curl -sS -H "Authorization: Bearer $RD_TOKEN" \
  "$BASE/streaming/mediaInfos/<FILE_ID>" | jq .
```

File IDs come from `/downloads` or `/unrestrict/link` (`id` field). Use these to build playback URLs for VLC, mpv, etc.

---

## Full Magnet-to-Disk Script

Standalone script the skill can invoke or the user can run directly:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Resolve token
if [ -n "${RD_API_TOKEN:-}" ]; then
  RD_TOKEN="$RD_API_TOKEN"
elif [ -f ~/.rd/config ]; then
  RD_TOKEN=$(grep -v '^#' ~/.rd/config | grep 'RD_API_TOKEN=' | head -1 | cut -d= -f2-)
fi
RD_TOKEN="${RD_TOKEN:?Set RD_API_TOKEN or create ~/.rd/config}"
BASE="https://api.real-debrid.com/rest/1.0"

MAGNET="${1:?Usage: rd-magnet <magnet-link> [download-dir]}"
DOWNLOAD_DIR="${2:-.}"

# Add magnet
echo "Adding magnet..."
TORRENT_ID=$(curl -sS -X POST \
  -H "Authorization: Bearer $RD_TOKEN" \
  -d "magnet=$MAGNET" \
  "$BASE/torrents/addMagnet" | jq -r '.id')
echo "Torrent ID: $TORRENT_ID"

# Poll
while true; do
  INFO=$(curl -sS -H "Authorization: Bearer $RD_TOKEN" \
    "$BASE/torrents/info/$TORRENT_ID")
  STATUS=$(echo "$INFO" | jq -r '.status')
  PROGRESS=$(echo "$INFO" | jq -r '.progress')
  SPEED=$(echo "$INFO" | jq -r '.speed // 0')

  echo "Status: $STATUS | Progress: ${PROGRESS}% | Speed: $(numfmt --to=iec $SPEED 2>/dev/null || echo "${SPEED}B/s")"

  case "$STATUS" in
    magnet_conversion|waiting_files_selection)
      if [ "$STATUS" = "waiting_files_selection" ]; then
        echo "Selecting all files..."
        curl -sS -X POST -H "Authorization: Bearer $RD_TOKEN" \
          -d "files=all" "$BASE/torrents/selectFiles/$TORRENT_ID" || true
      fi
      sleep 5
      ;;
    queued|downloading|compressing|uploading)
      sleep 10
      ;;
    downloaded)
      echo "Torrent ready!"
      break
      ;;
    *)
      echo "Error: $STATUS"
      exit 1
      ;;
  esac
done

# Download
LINKS=$(echo "$INFO" | jq -r '.links[]')
mkdir -p "$DOWNLOAD_DIR"
for LINK in $LINKS; do
  RESULT=$(curl -sS -X POST -H "Authorization: Bearer $RD_TOKEN" \
    -d "link=$LINK" "$BASE/unrestrict/link")
  FILENAME=$(echo "$RESULT" | jq -r '.filename')
  DIRECT=$(echo "$RESULT" | jq -r '.download')
  FILESIZE=$(echo "$RESULT" | jq -r '.filesize')
  echo "Downloading: $FILENAME ($(numfmt --to=iec $FILESIZE 2>/dev/null || echo "$FILESIZE bytes"))"
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 -C - \
    -o "$DOWNLOAD_DIR/$FILENAME" "$DIRECT"
done

# Cleanup
curl -sS -X DELETE -H "Authorization: Bearer $RD_TOKEN" \
  "$BASE/torrents/delete/$TORRENT_ID" 2>/dev/null || true

echo "Done! Files in: $DOWNLOAD_DIR"
```

---

## Error Reference

| HTTP | Meaning | Action |
|---|---|---|
| 401 | Bad token | Verify `RD_API_TOKEN` |
| 403 | Locked / not premium | Check `/user` |
| 404 | Not found | Wrong ID or deleted |
| 429 | Rate limited | Wait 60s, retry |
| 503 | Service down | Retry later |

Error body: `{"error": "message", "error_code": N}`

Key error codes: 1=missing param, 2=bad param, 8=bad token, 16=unsupported host, 24=file unavailable, 29=torrent too big, 33=already active, 34=too many requests.

---

## Tips

- **Host selection**: Pass `host=rd` when adding magnets to force Real-Debrid servers.
- **Background downloads**: `nohup curl ... &` for large files; monitor with `stat`.
- **Resume**: Always `curl -C -` for large files.
- **Torrent cleanup**: Delete after download to free RD active slots.
- **Selective files**: Show users the file list before selecting — saves bandwidth for multi-file torrents.
