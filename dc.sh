#!/usr/bin/env bash
# dc.sh — docker compose helper for the halogen stack.
#
# Usage:
#   ./dc.sh init                    copy .env.example + docker-compose.yml.example
#                                   (if missing) + build model-download
#   ./dc.sh init:override           copy docker-compose.override.yml.example
#   ./dc.sh download                fetch weights for the active .env set (one-shot)
#   ./dc.sh up [service ...]        start the stack (default: halogen; waits for download)
#   ./dc.sh down [args ...]         stop the stack
#   ./dc.sh restart                 recreate halogen after an .env set switch
#   ./dc.sh ps                      list containers
#   ./dc.sh logs [service ...]      tail logs (default: halogen)
#   ./dc.sh config                  print merged compose config
#   ./dc.sh build [service ...]     build images (default: model-download)
#
# First-time / after wiping ./models:
#   ./dc.sh init && ./dc.sh up
#   # or: docker compose up -d  (model-download runs first, then halogen)
#
# Switch sets: edit .env (one profile block active), then:
#   ./dc.sh download && ./dc.sh restart
#   # or: docker compose up -d --force-recreate
#
# GPU: VIDEO_GID / RENDER_GID are auto-detected; override with:
#   VIDEO_GID=44 RENDER_GID=999 ./dc.sh up

set -euo pipefail

cd "$(dirname "$0")"

COMPOSE="docker compose"

usage() {
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

compose_main() {
    if [ ! -f docker-compose.yml ]; then
        echo "Missing docker-compose.yml" >&2
        exit 1
    fi
    if [ ! -f .env ]; then
        echo "Missing .env. Run: ./dc.sh init" >&2
        exit 1
    fi
    local args=(-f docker-compose.yml)
    if [ -f docker-compose.override.yml ]; then
        args+=(-f docker-compose.override.yml)
    fi
    printf '%s\n' "${args[@]}"
}

cp_example() {
    local src="$1"
    local dest="$2"
    if [ ! -f "$src" ]; then
        echo "Missing example: $src" >&2
        return 1
    fi
    if [ -e "$dest" ]; then
        echo "==> skip $dest (already exists)"
        return 0
    fi
    cp "$src" "$dest"
    echo "==> created $dest from $src"
}

export_gpu_gids() {
    if [ -z "${VIDEO_GID:-}" ]; then
        VIDEO_GID="$(stat -c %g /dev/dri/card0 2>/dev/null \
            || getent group video | cut -d: -f3 2>/dev/null \
            || true)"
    fi
    if [ -z "${RENDER_GID:-}" ]; then
        RENDER_GID="$(stat -c %g /dev/dri/renderD128 2>/dev/null \
            || getent group render | cut -d: -f3 2>/dev/null \
            || true)"
    fi
    [ -n "${VIDEO_GID:-}" ] || { echo "WARN: VIDEO_GID not detected; set it manually." >&2; }
    [ -n "${RENDER_GID:-}" ] || { echo "WARN: RENDER_GID not detected; set it manually." >&2; }
    export VIDEO_GID RENDER_GID
    echo "==> GPU gids: video=${VIDEO_GID:-?} render=${RENDER_GID:-?}"
}

format_elapsed() {
    local total="${1:-0}"
    local h=$((total / 3600)) m=$(((total % 3600) / 60)) s=$((total % 60))
    if [ "$h" -gt 0 ]; then
        printf '%dh %02dm %02ds' "$h" "$m" "$s"
    elif [ "$m" -gt 0 ]; then
        printf '%dm %02ds' "$m" "$s"
    else
        printf '%ds' "$s"
    fi
}

wait_ready() {
    echo "Waiting for halogen (checkpoint load can take several minutes)..."
    local -a main
    local started=$SECONDS
    mapfile -t main < <(compose_main)
    for _ in $(seq 1 120); do
        if docker compose "${main[@]}" exec -T halogen \
            python3 -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8731/v1/models", timeout=3).read()' \
            >/dev/null 2>&1; then
            echo "halogen is ready ($(format_elapsed $((SECONDS - started))))."
            return 0
        fi
        sleep 10
    done
    echo "Timed out waiting for halogen after $(format_elapsed $((SECONDS - started))). Check ./dc.sh logs" >&2
    return 1
}

cmd="${1:-}"
shift || true

case "${cmd}" in
    init)
        echo "==> Initialising from examples (existing files are kept)"
        cp_example .env.example .env
        cp_example docker-compose.yml.example docker-compose.yml
        export_gpu_gids
        echo "==> Building model-download"
        mapfile -t MAIN < <(compose_main)
        ${COMPOSE} "${MAIN[@]}" build model-download
        echo "==> Done. Edit .env to pick a set, then: ./dc.sh up"
        echo "==> Optional tsdproxy: ./dc.sh init:override"
        ;;
    init:override)
        echo "==> Initialising docker-compose.override.yml"
        cp_example docker-compose.override.yml.example docker-compose.override.yml
        ;;
    download)
        export_gpu_gids
        echo "==> Downloading model weights for the active .env set (idempotent)"
        mapfile -t MAIN < <(compose_main)
        if [ -t 1 ]; then
            echo "==> Progress bars enabled (interactive TTY)"
            ${COMPOSE} "${MAIN[@]}" run --rm model-download
        else
            echo "==> No TTY: bars may be limited. Watch size with: watch -n2 du -sh ${MODELS_DIR:-./models}"
            ${COMPOSE} "${MAIN[@]}" run --rm -T model-download
        fi
        ;;
    up)
        services="${@:-halogen}"
        export_gpu_gids
        echo "==> Starting: ${services}"
        mapfile -t MAIN < <(compose_main)
        ${COMPOSE} "${MAIN[@]}" up -d ${services}
        wait_ready
        ;;
    down)
        mapfile -t MAIN < <(compose_main)
        ${COMPOSE} "${MAIN[@]}" down "$@"
        ;;
    restart)
        export_gpu_gids
        mapfile -t MAIN < <(compose_main)
        ${COMPOSE} "${MAIN[@]}" up -d --force-recreate halogen
        wait_ready
        ;;
    ps)
        mapfile -t MAIN < <(compose_main)
        ${COMPOSE} "${MAIN[@]}" ps "$@"
        ;;
    logs)
        services="${@:-halogen}"
        mapfile -t MAIN < <(compose_main)
        ${COMPOSE} "${MAIN[@]}" logs -f --tail=100 ${services}
        ;;
    build)
        services="${@:-model-download}"
        export_gpu_gids
        mapfile -t MAIN < <(compose_main)
        ${COMPOSE} "${MAIN[@]}" build ${services}
        ;;
    config)
        export_gpu_gids
        mapfile -t MAIN < <(compose_main)
        ${COMPOSE} "${MAIN[@]}" config
        ;;
    ""|-h|--help|help)
        usage
        ;;
    *)
        echo "Unknown command: ${cmd}" >&2
        echo >&2
        usage >&2
        exit 1
        ;;
esac
