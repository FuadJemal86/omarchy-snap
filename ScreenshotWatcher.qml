import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property string home: Quickshell.env("HOME")
  property string screenshotDir: home + "/Pictures/Screenshots"
  property string pluginId: "io.github.fuad.omarchy-snap"
  property var pendingImages: []

  function isImage(path) {
    return /\.(png|jpe?g|webp|bmp)$/i.test(path)
  }

  function openImage(path) {
    if (!isImage(path) || /\/omarchy-snap-[^/]+\.(png|gif)$/i.test(path)) return
    var next = pendingImages.slice()
    next.push(path)
    pendingImages = next
    summonNext()
  }

  function summonNext() {
    if (summon.running || pendingImages.length === 0) return
    var next = pendingImages.slice()
    var path = next.shift()
    pendingImages = next
    summon.command = ["omarchy-shell", "shell", "summon", pluginId, JSON.stringify({ image: path })]
    summon.running = true
  }

  Process {
    id: watcher
    command: ["inotifywait", "-m", "-e", "close_write,moved_to", "--format", "%w%f", root.screenshotDir]
    stdout: SplitParser {
      onRead: function(line) { root.openImage(String(line).trim()) }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) restartTimer.start()
    }
  }
  Process { id: summon; onExited: root.summonNext() }
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
