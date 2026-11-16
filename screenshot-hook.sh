#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: screenshot-hook.sh <saved-image-path>" >&2
  exit 2
fi

image_path=$(realpath -e -- "$1")
case "${image_path,,}" in
  *.png|*.jpg|*.jpeg|*.webp|*.bmp) ;;
  *) echo "Unsupported screenshot format" >&2; exit 2 ;;
esac

payload=$(python -c 'import json, sys; print(json.dumps({"image": sys.argv[1]}))' "$image_path")
exec omarchy-shell shell summon io.github.fuad.omarchy-snap "$payload"
