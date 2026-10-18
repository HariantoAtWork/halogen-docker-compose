# Halogen (Docker Compose)

Docker Compose stack for the [Halogen](https://github.com/peonist-ai) flash server on AMD Strix Halo (ROCm-style GPU devices, optional NPU sidecars).

Weights are pulled by a one-shot `model-download` service; `halogen` starts only after that finishes successfully.

## Requirements

- Docker Compose v2
- AMD GPU devices: `/dev/kfd`, `/dev/dri` (and `/dev/accel/accel0` when present)
- Optional: `HF_TOKEN` in `.env` if Hugging Face needs auth for the repos you use

`VIDEO_GID` / `RENDER_GID` are detected by `./dc.sh` when you use that helper; override if needed:

```bash
VIDEO_GID=44 RENDER_GID=999 ./dc.sh up
```

## Quick start

Compose templates and `.env` are not committed (see `.gitignore`). Initialise once after clone:

```bash
./dc.sh init
# edit .env if you want another model set (default is peonist stock v2)
./dc.sh up
# or: docker compose up -d
```

First start can take a while (Hub download + checkpoint load). `./dc.sh up` waits until the API answers on port `8731`.

Optional Tailscale/tsdproxy override:

```bash
./dc.sh init:override
```

## Model sets

Exactly **one** profile block in `.env` should be active (see `.env.example`):

| Set | Description |
|-----|-------------|
| **A** | peonist stock v2 (default) |
| **B** | peonist stock HT43 (smaller) |
| **C** | Quat3rnion v2 abliterated (+ peonist companions) |
| **D** | Quat3rnion HT43 abliterated (experimental) |

To switch: comment out the active block, uncomment another, then:

```bash
./dc.sh download && ./dc.sh restart
# or: docker compose up -d --force-recreate
```

## Commands (`./dc.sh`)

| Command | What it does |
|---------|----------------|
| `init` | Copy `.env` + `docker-compose.yml` from examples; build the downloader |
| `init:override` | Copy `docker-compose.override.yml` (tsdproxy) |
| `up` | Start stack (download first, then halogen); wait until ready |
| `download` | Fetch weights only (idempotent) |
| `restart` | Recreate halogen (e.g. after an `.env` set switch) |
| `logs` | Tail logs (default: halogen) |
| `ps` | List containers |
| `down` | Stop the stack |
| `build` | Build images (default: model-download) |
| `config` | Print merged Compose config |

Plain Compose works too: `docker compose up -d` runs `model-download`, then starts `halogen`.

## Notes

- Weights live in `./models/` (gitignored). Re-runs of the downloader skip files that are already present.
- NPU sidecars are controlled by `HALOGEN_NPU_MODELS` (empty = Flash only). With `HALOGEN_DOWNLOAD` set, NPU pieces can still fetch on first server start.
- Default host port: `8731` (`HALOGEN_HOST_PORT`).
