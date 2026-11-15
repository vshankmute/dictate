#!/bin/bash
# Downloads one of the three preset models from the command line (the app itself never downloads anything:
# its Download… button opens the browser). Checksums are SHA1 from the whisper.cpp models table.
# Usage: bash get-model.sh [large-v3-turbo | large-v3 | large-v3-turbo-q5_0]   (default: large-v3-turbo)
set -euo pipefail

model="${1:-large-v3-turbo}"
case "$model" in
    large-v3-turbo)      expected=4af2b29d7ec73d781377bfd1758ca957a807e941 ;;  # 1.6 GB
    large-v3)            expected=ad82bf6a9043ceed055076d0fd39f5f186ff8062 ;;  # 3.1 GB
    large-v3-turbo-q5_0) expected=e050f7970618a659205450ad97eb95a18d69c9ee ;;  # 574 MB
    *) echo "Unknown model: $model. Use large-v3-turbo, large-v3 or large-v3-turbo-q5_0." >&2; exit 1 ;;
esac
name="ggml-$model.bin"
dir="$HOME/Library/Application Support/Dictate"

mkdir -p "$dir"
curl -L --fail --progress-bar -o "$dir/$name.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$name"
actual=$(shasum -a 1 "$dir/$name.part" | cut -d' ' -f1)
if [ "$actual" != "$expected" ]; then
    rm -f "$dir/$name.part"
    echo "Checksum mismatch: got $actual, expected $expected. File deleted." >&2
    exit 1
fi
mv "$dir/$name.part" "$dir/$name"
echo "Model OK (checksum verified): $dir/$name"
