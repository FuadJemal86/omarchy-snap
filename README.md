# Omarchy Snap

Local Omarchy shell plugin for opening screenshots in a drawing and sticker overlay.

Enable it with `omarchy plugin enable io.github.fuad.omarchy-snap`. The background watcher uses `inotifywait` from `inotify-tools`; exporting uses `ffmpeg` and `wl-copy` from `wl-clipboard`. Put animated `.gif` stickers in this plugin's `assets/` directory. New PNG, JPEG, WebP, and BMP files written to `~/Pictures/Screenshots` open automatically.

The overlay supports freehand marks, emoji stamps, movable GIFs, Ctrl+Z, PNG export, and a 2.5 second animated GIF capture when a GIF sticker is present.
# omarchy-snap
