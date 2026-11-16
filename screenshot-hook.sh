#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: screenshot-hook.sh <saved-image-path>" >&2
  exit 2
fi

image_path=$(realpath -e -- "$1")
case "${image_path,,}" in
  *.png) ;;
  *) echo "Unsupported screenshot format" >&2; exit 2 ;;
esac

trigger_file=/tmp/omarchy-snap-open.txt
trigger_tmp=$(mktemp /tmp/omarchy-snap-open.XXXXXX)
trap 'rm -f -- "$trigger_tmp"' EXIT
printf '%s\n' "$image_path" > "$trigger_tmp"
mv -fT -- "$trigger_tmp" "$trigger_file"
trap - EXIT
