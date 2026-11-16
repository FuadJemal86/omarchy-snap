# Omarchy Snap

Omarchy Snap adds emoji and animated GIF stickers to the screenshot workflow. Omasnap continues to handle capture, region selection, and drawing. Enable the plugin with `omarchy plugin enable io.github.fuad.omarchy-snap`; the service watches `~/Pictures/Screenshots`, `~/Pictures`, any `OMASNAP_SCREENSHOT_DIR` or `OMARCHY_SCREENSHOT_DIR` override, and `/tmp/omarchy-snap-open.txt` for new PNG captures or hook triggers. A new screenshot shows an **Add stickers** notification button; clicking it opens that image in the overlay.

The overlay includes six quick emoji stamps, a larger sticker library, bundled animated GIFs from `assets/`, and an **Add GIF…** picker for local `.gif` and `.webp` files. The editor hides while the native file picker is open and returns when you choose a file or cancel. Drag stickers to position them, use the mouse wheel to resize, then select one and choose **Remove** (or press Delete). Escape closes the overlay. Save / Copy writes a PNG when there are no GIF stickers, or captures 2.5 seconds of frames and uses ffmpeg to make a looping GIF when there are.

Runtime tools: `inotifywait` from `inotify-tools`, `head`, `ffmpeg`, and `wl-copy` from `wl-clipboard`. Run `./setup-screenshot-hook.sh` to install an executable `~/.config/omarchy/hooks/screenshot`; call it through `omarchy hook screenshot /path/to/saved-image.png` after saving. Direct IPC testing uses `qs ipc -p "$OMARCHY_PATH/shell" call omarchy-snap open /path/to/image.png`.
# omarchy-snap
