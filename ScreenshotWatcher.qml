import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property string home: Quickshell.env("HOME")
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  property string picturesDir: home + "/Pictures"
  property string configuredDir: Quickshell.env("OMASNAP_SCREENSHOT_DIR") || Quickshell.env("OMARCHY_SCREENSHOT_DIR") || ""
  property string screenshotDir: configuredDir || picturesDir + "/Screenshots"
  property string triggerPath: "/tmp/omarchy-snap-open.txt"
  property string pluginId: "io.github.fuad.omarchy-snap"
  property var pendingImages: []
  property string lastImage: ""
  property double lastImageTime: 0
  readonly property var watchDirectories: screenshotDir === picturesDir
    ? [screenshotDir, "/tmp"] : [screenshotDir, picturesDir, "/tmp"]

  function isImage(path) {
    return String(path || "").length <= 4096 && /^\/.+\.png$/i.test(String(path || ""))
  }

  function openImage(path, waitForSatty) {
    path = String(path || "").trim()
    if (!isImage(path) || /\/omarchy-snap-[^/]+\.png$/i.test(path)) return
    var now = Date.now()
    if (path === lastImage && now - lastImageTime < 20000) {
      if (waitForSatty === false) launchImage(path)
      return
    }
    lastImage = path
    lastImageTime = now
    if (waitForSatty === false) { launchImage(path); return }
    var next = pendingImages.slice()
    next.push(path)
    pendingImages = next
    notifyNext()
  }

  function notifyNext() {
    if (stickerNotice.running || pendingImages.length === 0) return
    var next = pendingImages.slice()
    var path = next.shift()
    pendingImages = next
    notifyStickers(path)
  }

  function launchImage(path) {
    summon.command = [root.omarchyPath + "/bin/omarchy-shell", "shell", "summon", pluginId, JSON.stringify({ image: path })]
    summon.running = true
  }

  function notifyStickers(path) {
    var payload = JSON.stringify({ image: path })
    stickerNotice.command = [
      root.omarchyPath + "/bin/omarchy-notification-send", "--app-name", "Omarchy Snap",
      "Screenshot ready", "Add emojis or GIF stickers to this image.",
      "--transient", "--expire-time", "20000",
      "--action", "Add stickers", root.omarchyPath + "/bin/omarchy-shell", "shell", "summon", pluginId,
      "--with", payload
    ]
    stickerNotice.running = true
  }

  Process {
    id: watcher
    command: ["inotifywait", "-m", "-e", "create,close_write,moved_to", "--format", "%w%f"].concat(root.watchDirectories)
    stdout: SplitParser {
      onRead: function(line) {
        var path = String(line).trim()
        if (path === root.triggerPath) triggerRead.running = true
        else if (/\.png$/i.test(path)) root.openImage(path)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) restartTimer.start()
    }
  }
  Process { id: summon; onExited: root.notifyNext() }
  Process { id: stickerNotice; onExited: root.notifyNext() }
  Process {
    id: triggerRead
    command: ["head", "-c", "4097", root.triggerPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.openImage(String(text || ""))
    }
  }
  IpcHandler {
    target: "omarchy-snap"
    function open(path: string): string {
      root.openImage(path, false)
      return "opening"
    }
  }
  Timer {
    id: restartTimer
    interval: 5000
    repeat: false
    onTriggered: if (!watcher.running) watcher.running = true
  }
  Process {
    id: directoryCheck
    command: ["mkdir", "-p", root.screenshotDir]
    onExited: function(code) { if (code === 0 && !watcher.running) watcher.running = true }
  }
  Component.onCompleted: directoryCheck.running = true
}
