# Omarchy Snap

Omarchy Snap adds emoji and animated GIF stickers to the screenshot workflow. Omasnap continues to handle capture, region selection, and drawing. Enable the plugin with `omarchy plugin enable io.github.fuad.omarchy-snap`; the service watches `~/Pictures/Screenshots` and opens new saved images in the sticker overlay.

The overlay includes six emoji stamps, bundled animated GIFs from `assets/`, and an **Add GIF…** picker for local `.gif` and `.webp` files. Drag stickers to position them and use the mouse wheel to resize. Escape closes the overlay. Save & Copy writes a PNG when there are no GIF stickers, or captures 2.5 seconds of frames and uses ffmpeg to make a looping GIF when there are.

Runtime tools: `inotifywait` from `inotify-tools`, `ffmpeg`, `wl-copy` from `wl-clipboard`, and Python 3 for JSON escaping in the optional hook. The directory watcher is the automatic integration with the installed Omasnap flow. For another screenshot command that can invoke hooks, install the optional hook with `./setup-screenshot-hook.sh`, then call `omarchy hook screenshot /path/to/saved-image.png` after saving.
# omarchy-snap
