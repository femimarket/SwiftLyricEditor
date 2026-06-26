#!/usr/bin/env bash
# Downloads the Qwen3-ASR-ForcedAligner-0.6B model into the project's source
# tree so it can be bundled in the app. Drag the resulting folder into the
# LyricEditor target as a folder reference (blue folder).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODEL_DIR="$REPO_ROOT/LyricEditor/qwen3-aligner-0.6b"
HF_REPO="Qwen/Qwen3-ASR-ForcedAligner-0.6B"
FILES=(
    "model.safetensors.index.json"
    "model-00001-of-00002.safetensors"
    "model-00002-of-00002.safetensors"
    "vocab.json"
    "merges.txt"
)

mkdir -p "$MODEL_DIR"
cd "$MODEL_DIR"

AUTH_HEADER=()
if [ -n "${HF_TOKEN:-}" ]; then
    AUTH_HEADER=(-H "Authorization: Bearer ${HF_TOKEN}")
else
    echo "[note] HF_TOKEN not set — model may require auth. Get a token from"
    echo "       https://huggingface.co/settings/tokens and re-run with:"
    echo "         HF_TOKEN=hf_xxx $0"
fi

for f in "${FILES[@]}"; do
    if [ -s "$f" ]; then
        echo "[skip] $f already present"
        continue
    fi
    echo "[get ] $f"
    curl -L --fail --progress-bar \
        "${AUTH_HEADER[@]}" \
        -o "$f" \
        "https://huggingface.co/${HF_REPO}/resolve/main/${f}"
done

echo
echo "Model staged at: $MODEL_DIR"
echo "In Xcode, drag this folder into the LyricEditor target as a folder reference"
echo "(blue folder) so its contents bundle as a directory in the .app."
