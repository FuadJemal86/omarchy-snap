#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
hook_dir=${XDG_CONFIG_HOME:-"$HOME/.config"}/omarchy/hooks
hook_path=$hook_dir/screenshot
mkdir -p -- "$hook_dir"

if [[ -e "$hook_path" ]] && ! cmp -s -- "$script_dir/screenshot-hook.sh" "$hook_path"; then
  echo "Refusing to replace existing hook: $hook_path" >&2
  exit 1
fi

install -m 0755 -- "$script_dir/screenshot-hook.sh" "$hook_path"
chmod +x -- "$hook_path"

# Earlier Omarchy Snap installs used a .d hook that summoned the panel directly.
# Remove only that identifiable plugin-owned legacy hook so it cannot bypass
# the trigger file or summon a duplicate overlay before Satty closes.
legacy_hook=$hook_dir/screenshot.d/screenshot-hook.sh
if [[ -f "$legacy_hook" && ! -L "$legacy_hook" ]] \
    && grep -Fq 'omarchy-shell shell summon io.github.fuad.omarchy-snap' "$legacy_hook"; then
  rm -- "$legacy_hook"
fi

echo "Installed executable screenshot hook: $hook_path"
