# real-debrid-skill

Full Real-Debrid API integration for **Pi** and **Oh My Pi**. Feed it magnet links, hoster URLs, or just ask about your account — the agent handles the rest.

Also ships a standalone CLI (`rd`) for use outside the agent.

## What it does

| Feature | Example |
|---|---|
| **Magnet → download** | "Download this magnet: magnet:?xt=urn:btih:..." |
| **Hoster unrestrict** | "Unrestrict this mega link: https://mega.nz/..." |
| **Account info** | "What's my RD premium status?" |
| **Traffic monitoring** | "How much traffic do I have left?" |
| **Torrent management** | "List my active torrents" |
| **Streaming URLs** | "Get me a streaming link for this file" |

## Install

### As a Pi / Oh My Pi skill

**Option A — Marketplace (recommended)**:

```
/marketplace add subhash/real-debrid-skill
/marketplace install real-debrid@real-debrid-skill
```

**Option B — Manual**:

Clone or copy the `plugins/real-debrid/` directory into your skills path:

```bash
# User skills (~/.omp/agent/skills/)
git clone https://github.com/subhash/real-debrid-skill.git /tmp/rd-skill
mkdir -p ~/.omp/agent/skills/real-debrid
cp /tmp/rd-skill/plugins/real-debrid/SKILL.md ~/.omp/agent/skills/real-debrid/
```

### As a standalone CLI

```bash
git clone https://github.com/subhash/real-debrid-skill.git
sudo ln -s "$(pwd)/real-debrid-skill/rd" /usr/local/bin/rd
```

## Setup

### 1. Get your API token

Go to https://real-debrid.com/apitoken (requires a Real-Debrid account).

### 2. Configure the token

**Option A — Environment variable** (recommended):

```bash
# Add to ~/.bashrc, ~/.zshrc, or ~/.profile
export RD_API_TOKEN="your_token_here"
```

**Option B — Config file**:

```bash
mkdir -p ~/.rd
echo "RD_API_TOKEN=your_token_here" > ~/.rd/config
```

The env var takes precedence over the config file.

### 3. Verify

```bash
# CLI
rd user

# Or just ask the agent:
# "What's my Real-Debrid account status?"
```

## CLI Usage

```bash
rd add "magnet:?xt=urn:btih:..." [download-dir]   # Magnet → download
rd unrestrict "https://mega.nz/..." [download-dir] # Unrestrict hoster link
rd check "https://mega.nz/..."                      # Check if supported
rd user                                             # Account info
rd traffic                                          # Traffic usage
rd downloads [limit]                                # Recent downloads
rd torrents [active]                                # List torrents
rd info <torrent-id>                                # Torrent details
rd delete <torrent-id>                              # Delete torrent
rd convert-points                                   # Convert fidelity points
```

## Agent Usage

Once installed as a skill, just talk to the agent naturally:

- *"Download this magnet link to /data/media: magnet:?xt=..."*
- *"Unrestrict this rapidgator link and download it"*
- *"How much premium time do I have left?"*
- *"Show me my active torrents"*
- *"What files are in torrent abc123?"*

The agent will handle polling, file selection, downloading, and cleanup automatically.

## Requirements

- `curl` and `jq` (the agent uses these for all API calls)
- A Real-Debrid premium account (free accounts have very limited hoster support)

## API Coverage

| Endpoint | Used by |
|---|---|
| `/torrents/addMagnet` | Magnet workflow |
| `/torrents/info/{id}` | Status polling |
| `/torrents/selectFiles/{id}` | File selection |
| `/torrents/delete/{id}` | Cleanup |
| `/torrents` | List torrents |
| `/unrestrict/link` | Direct download URLs |
| `/unrestrict/check` | Link validation |
| `/unrestrict/folder` | Folder unrestrict |
| `/user` | Account info |
| `/traffic` | Traffic usage |
| `/traffic/details` | Traffic by date |
| `/downloads` | Download history |
| `/downloads/delete/{id}` | Delete downloads |
| `/streaming/transcode/{id}` | Streaming URLs |
| `/streaming/mediaInfos/{id}` | Media metadata |
| `/settings/convertPoints` | Fidelity points |

## License

MIT
