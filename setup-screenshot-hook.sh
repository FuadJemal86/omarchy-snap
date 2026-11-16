#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec omarchy hook install screenshot "$script_dir/screenshot-hook.sh"
