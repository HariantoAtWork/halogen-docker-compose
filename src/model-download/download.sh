#!/usr/bin/env sh
# Multi-repo Halogen weight fetch.
#
# HF_DOWNLOAD_SPECS: one "repo|revision|artifact" per whitespace-separated
# token (newlines inside a quoted .env value are fine). artifact is either:
#   - a single Hub path (e.g. qwen38-flash-next-ngram.hgn)
#   - include:GLOB   → hf download --include GLOB (e.g. include:tokenizer/*)
#
# Everything lands flat under /workspace/models so the Halogen server can
# find companions beside HALOGEN_CHECKPOINT.
set -eu

export HF_HUB_DISABLE_PROGRESS_BARS=0
export PYTHONUNBUFFERED=1

: "${HF_DOWNLOAD_SPECS:?set HF_DOWNLOAD_SPECS (see .env.example)}"

dest="/workspace/models"
mkdir -p "$dest"

# Run `hf` under a PTY so tqdm/xet bars render even without `docker -t`.
hf_progress() {
	python - "$@" <<'PY'
import os, pty, sys

os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "0"
argv = ["hf", *sys.argv[1:]]
status = pty.spawn(argv)
if os.WIFEXITED(status):
    raise SystemExit(os.WEXITSTATUS(status))
if os.WIFSIGNALED(status):
    raise SystemExit(128 + os.WTERMSIG(status))
raise SystemExit(1)
PY
}

# Flatten whitespace (including newlines) into positional args.
# shellcheck disable=SC2086
set -- $HF_DOWNLOAD_SPECS

total=$#
if [ "$total" -eq 0 ]; then
	echo "HF_DOWNLOAD_SPECS is empty" >&2
	exit 1
fi

echo "==> Downloading $total artifact(s) → $dest"

i=0
for spec in "$@"; do
	i=$((i + 1))
	repo=${spec%%|*}
	rest=${spec#*|}
	rev=${rest%%|*}
	artifact=${rest#*|}

	if [ -z "$repo" ] || [ -z "$rev" ] || [ -z "$artifact" ] || [ "$artifact" = "$rest" ]; then
		echo "bad spec [$i/$total]: expected repo|revision|artifact, got: $spec" >&2
		exit 1
	fi

	echo
	echo "==> [$i/$total] $repo @ $rev → $artifact"
	case "$artifact" in
	include:*)
		glob=${artifact#include:}
		hf_progress download "$repo" \
			--revision "$rev" \
			--repo-type model \
			--include "$glob" \
			--local-dir "$dest" \
			--format human
		;;
	*)
		hf_progress download "$repo" "$artifact" \
			--revision "$rev" \
			--repo-type model \
			--local-dir "$dest" \
			--format human
		;;
	esac
done

echo
echo "==> Done. Flash weights under $dest"
echo "    NPU models (if HALOGEN_NPU_MODELS is set) still fetch on first server start when HALOGEN_DOWNLOAD is set."
