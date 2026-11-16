# Omarchy Snap

Omarchy Snap adds emoji and animated GIF stickers to the Omarchy screenshot workflow. After taking a screenshot, click **Add stickers** in its notification to open the editor.

## Install

Omarchy Snap is installed directly from [FuadJemal86/omarchy-snap](https://github.com/FuadJemal86/omarchy-snap). Copy and paste these commands into a terminal:

```bash
# Install the runtime tools used for watching screenshots, animated exports, and clipboard copy.
omarchy pkg add inotify-tools ffmpeg wl-clipboard

# Clone, validate, and enable Omarchy Snap.
omarchy plugin add https://github.com/FuadJemal86/omarchy-snap.git --enable --yes
```

Confirm that it is installed and enabled:

```bash
omarchy plugin list
```

The plugin ID is `io.github.fuad.omarchy-snap`. If it is listed but disabled, enable it with:

```bash
omarchy plugin enable io.github.fuad.omarchy-snap
```

## Use

1. Take a screenshot with your normal Omarchy screenshot shortcut or `omarchy capture screenshot`.
2. Click **Add stickers** in the screenshot notification.
3. Add emoji or GIF stickers, drag them into place, and use the wheel to resize a selected sticker.
4. Use the brush or eraser for markup. The **Fit to window** button (or `0`) recenters and restores the automatic image scale.
5. Choose **Save / Copy** to export. Static edits export as PNG; edits containing GIF stickers can export as an animated GIF or MP4.

The watcher detects PNG screenshots in `~/Pictures/Screenshots`, `~/Pictures`, and any directory specified through `OMASNAP_SCREENSHOT_DIR` or `OMARCHY_SCREENSHOT_DIR`.

## Optional Screenshot Hook

If your own screenshot script saves an image outside those directories, install the included hook after adding the plugin:

```bash
cd ~/.config/omarchy/plugins/io.github.fuad.omarchy-snap
./setup-screenshot-hook.sh
```

The installer protects an existing `~/.config/omarchy/hooks/screenshot` hook and stops instead of replacing it. From your screenshot script, call the hook after saving a PNG:

```bash
omarchy hook screenshot /path/to/saved-image.png
```

## Update or Remove

```bash
# Get the latest version from GitHub.
omarchy plugin update io.github.fuad.omarchy-snap --yes

# Disable and remove the plugin.
omarchy plugin remove io.github.fuad.omarchy-snap --yes
```

## Features

- Quick emoji stamps and a searchable emoji library.
- Bundled and local `.gif` / `.webp` stickers, plus `.mp4` clips converted to looping GIFs up to four seconds long.
- Sticker drag, resize, rotation, duplication, undo/redo, drawing, and erasing.
- PNG, animated GIF, and MP4 export.

## Troubleshooting

Restart the Omarchy shell if the plugin does not appear after installation:

```bash
omarchy restart shell
```

For direct IPC testing, open an existing PNG in the editor with:

```bash
qs ipc -p "$OMARCHY_PATH/shell" call omarchy-snap open /path/to/image.png
```
