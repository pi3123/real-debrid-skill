#!/usr/bin/env bash
set -euo pipefail

# rd — Real-Debrid CLI
# Usage: rd <command> [args]
#
# Commands:
#   add <magnet> [dir]        Add magnet, poll, download
#   unrestrict <link> [dir]   Unrestrict hoster link, download
#   check <link>              Check if link is supported
#   user                      Account info
#   traffic                   Traffic usage
#   downloads [limit]         List recent downloads
#   torrents [filter]         List torrents (filter: active)
#   info <torrent-id>         Torrent details
#   delete <torrent-id>       Delete torrent
#   convert-points            Convert fidelity points

# --- Token resolution ---
resolve_token() {
  if [ -n "${RD_API_TOKEN:-}" ]; then
    echo "$RD_API_TOKEN"
  elif [ -f ~/.rd/config ]; then
    local token
    token=$(grep -v '^#' ~/.rd/config | grep 'RD_API_TOKEN=' | head -1 | cut -d= -f2-)
    if [ -n "$token" ]; then
      echo "$token"
    else
      echo "Error: No RD_API_TOKEN in ~/.rd/config" >&2
      exit 1
    fi
  else
    echo "Error: Set RD_API_TOKEN env var or create ~/.rd/config" >&2
    echo "  ~/.rd/config format: RD_API_TOKEN=your_token_here" >&2
    exit 1
  fi
}

RD_TOKEN=""
BASE="https://api.real-debrid.com/rest/1.0"

ensure_token() {
  if [ -z "$RD_TOKEN" ]; then
    RD_TOKEN=$(resolve_token)
  fi
}

rd_api() {
  ensure_token
  local method="$1" endpoint="$2"
  shift 2
  curl -sS -X "$method" \
    -H "Authorization: Bearer $RD_TOKEN" \
    "$@" \
    "$BASE$endpoint"
}

# --- Commands ---
cmd_add() {
  local magnet="${1:?Usage: rd add <magnet> [download-dir]}"
  local dir="${2:-.}"

  echo "Adding magnet..."
  local torrent_id
  torrent_id=$(rd_api POST /torrents/addMagnet -d "magnet=$magnet" | jq -r '.id')
  echo "Torrent ID: $torrent_id"

  while true; do
    local info status progress speed
    info=$(rd_api GET "/torrents/info/$torrent_id")
    status=$(echo "$info" | jq -r '.status')
    progress=$(echo "$info" | jq -r '.progress')
    speed=$(echo "$info" | jq -r '.speed // 0')

    printf "\r  Status: %-25s Progress: %3s%% Speed: %s" \
      "$status" "$progress" "$(numfmt --to=iec "$speed" 2>/dev/null || echo "${speed}B/s")"

    case "$status" in
      magnet_conversion)
        sleep 5
        ;;
      waiting_files_selection)
        echo ""
        echo "Files:"
        echo "$info" | jq -r '.files[] | "  [\(.id)] \(.path) (\(.bytes | . / 1048576 | floor)MB) selected=\(.selected)"'
        echo ""
        echo "Selecting all files..."
        rd_api POST "/torrents/selectFiles/$torrent_id" -d "files=all" || true
        sleep 3
        ;;
      queued|downloading|compressing|uploading)
        sleep 10
        ;;
      downloaded)
        echo ""
        echo "Torrent ready!"
        break
        ;;
      *)
        echo ""
        echo "Error: $status"
        exit 1
        ;;
    esac
  done

  # Download
  local links
  links=$(rd_api GET "/torrents/info/$torrent_id" | jq -r '.links[]')
  mkdir -p "$dir"
  for link in $links; do
    local result filename direct filesize
    result=$(rd_api POST /unrestrict/link -d "link=$link")
    filename=$(echo "$result" | jq -r '.filename')
    direct=$(echo "$result" | jq -r '.download')
    filesize=$(echo "$result" | jq -r '.filesize')
    echo "Downloading: $filename ($(numfmt --to=iec "$filesize" 2>/dev/null || echo "$filesize bytes"))"
    curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 -C - \
      -o "$dir/$filename" "$direct"
  done

  # Cleanup
  rd_api DELETE "/torrents/delete/$torrent_id" 2>/dev/null || true
  echo "Done! Files in: $dir"
}

cmd_unrestrict() {
  local link="${1:?Usage: rd unrestrict <link> [download-dir]}"
  local dir="${2:-.}"

  echo "Unrestricting..."
  local result
  result=$(rd_api POST /unrestrict/link -d "link=$link")
  local filename direct filesize
  filename=$(echo "$result" | jq -r '.filename')
  direct=$(echo "$result" | jq -r '.download')
  filesize=$(echo "$result" | jq -r '.filesize')

  echo "File: $filename ($(numfmt --to=iec "$filesize" 2>/dev/null || echo "$filesize bytes"))"
  mkdir -p "$dir"
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 -C - \
    -o "$dir/$filename" "$direct"
  echo "Done: $dir/$filename"
}

cmd_check() {
  local link="${1:?Usage: rd check <link>}"
  rd_api POST /unrestrict/check -d "link=$link" | jq .
}

cmd_user() {
  rd_api GET /user | jq .
}

cmd_traffic() {
  rd_api GET /traffic | jq .
}

cmd_downloads() {
  local limit="${1:-20}"
  rd_api GET "/downloads?limit=$limit" | jq .
}

cmd_torrents() {
  local filter="${1:-}"
  if [ -n "$filter" ]; then
    rd_api GET "/torrents?filter=$filter" | jq .
  else
    rd_api GET /torrents | jq .
  fi
}

cmd_info() {
  local id="${1:?Usage: rd info <torrent-id>}"
  rd_api GET "/torrents/info/$id" | jq .
}

cmd_delete() {
  local id="${1:?Usage: rd delete <torrent-id>}"
  rd_api DELETE "/torrents/delete/$id"
  echo "Deleted torrent $id"
}

cmd_convert_points() {
  rd_api POST /settings/convertPoints
  echo "Points converted"
}

cmd_help() {
  cat <<'EOF'
rd — Real-Debrid CLI

Usage: rd <command> [args]

Commands:
  add <magnet> [dir]        Add magnet link, poll, download files
  unrestrict <link> [dir]   Unrestrict hoster link, download
  check <link>              Check if a link is supported
  user                      Show account info
  traffic                   Show traffic usage
  downloads [limit]         List recent downloads (default: 20)
  torrents [filter]         List torrents (filter: "active")
  info <torrent-id>         Show torrent details
  delete <torrent-id>       Delete a torrent
  convert-points            Convert fidelity points
  help                      Show this help

Config:
  Set RD_API_TOKEN env var, or create ~/.rd/config with:
    RD_API_TOKEN=your_token_here

  Get your token: https://real-debrid.com/apitoken
EOF
}

# --- Dispatch ---
case "${1:-help}" in
  add)           shift; cmd_add "$@" ;;
  unrestrict)    shift; cmd_unrestrict "$@" ;;
  check)         shift; cmd_check "$@" ;;
  user)          cmd_user ;;
  traffic)       cmd_traffic ;;
  downloads)     shift; cmd_downloads "$@" ;;
  torrents)      shift; cmd_torrents "$@" ;;
  info)          shift; cmd_info "$@" ;;
  delete)        shift; cmd_delete "$@" ;;
  convert-points) cmd_convert_points ;;
  help|--help|-h) cmd_help ;;
  *)             echo "Unknown command: $1" >&2; cmd_help; exit 1 ;;
esac
