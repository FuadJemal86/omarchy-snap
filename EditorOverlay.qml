import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root
  property bool opened: false
  property string imagePath: ""
  property string outputDir: Quickshell.env("HOME") + "/Pictures/Screenshots"
  property var emojiItems: []
  property var gifItems: []
  property var bundledGifs: [Qt.resolvedUrl("assets/sparkle.gif"), Qt.resolvedUrl("assets/party.gif")]
  property bool exporting: false
  property int framesWritten: 0
  property string captureDir: "/tmp/omarchy-snap-" + Qt.createUuid().toString().replace(/[{}-]/g, "")
  property string gifOutputPath: ""
  readonly property bool hasAnimatedStickers: gifItems.length > 0

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) } catch (e) { payload = {} }
    var path = String(payload.image || "")
    if (!path || path.length > 4096) return
    imagePath = path
    emojiItems = []
    gifItems = []
    opened = true
    Qt.callLater(function() { previewArea.forceActiveFocus() })
  }

  function close() { opened = false; exporting = false }

  function addEmoji(value) {
    if (!imageCanvas.width || !imageCanvas.height) return
    var next = emojiItems.slice()
    next.push({ text: value, x: imageCanvas.width * 0.44, y: imageCanvas.height * 0.4, size: 48 })
    emojiItems = next
  }

  function addGif(url) {
    if (!url || !imageCanvas.width || !imageCanvas.height) return
    var next = gifItems.slice()
    next.push({ source: String(url), x: imageCanvas.width * 0.42, y: imageCanvas.height * 0.38, size: 112 })
    gifItems = next
  }

  function addCustomGif() {
    customGifDialog.open()
  }

  function exportImage() {
    if (exporting || !opened || sourceImage.status !== Image.Ready) return
    exporting = true
    if (hasAnimatedStickers) startGifExport()
    else savePng()
  }

  function savePng() {
    imageCanvas.grabToImage(function(result) {
      var path = root.outputDir + "/omarchy-snap-" + Date.now() + ".png"
      if (!result.saveToFile(path)) { root.exporting = false; return }
      clipboard.command = ["bash", "-lc", "wl-copy --type image/png < " + Util.shellQuote(path)]
      clipboard.running = true
    })
  }

  function startGifExport() {
    framesWritten = 0
    gifOutputPath = outputDir + "/omarchy-snap-" + Date.now() + ".gif"
    makeFrameDir.running = true
  }

  function captureFrame() {
    if (framesWritten >= 38) { encodeGif.running = true; return }
    var frame = framesWritten
    imageCanvas.grabToImage(function(result) {
      var path = root.captureDir + "/frame-" + ("000" + frame).slice(-3) + ".png"
      if (!result.saveToFile(path)) { root.exporting = false; return }
      root.framesWritten = frame + 1
      frameTimer.start()
    })
  }

  FileDialog {
    id: customGifDialog
    title: "Add animated sticker"
    fileMode: FileDialog.OpenFile
    nameFilters: ["Animated images (*.gif *.webp)"]
    onAccepted: root.addGif(selectedFile)
  }

  Process {
    id: makeFrameDir
    command: ["mkdir", "-p", root.captureDir]
    onExited: function(code) { if (code === 0) root.captureFrame(); else root.exporting = false }
  }
  Process {
    id: encodeGif
    command: ["ffmpeg", "-y", "-framerate", "15", "-i", root.captureDir + "/frame-%03d.png", "-loop", "0", "-vf", "split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse", root.gifOutputPath]
    onExited: function(code) {
      if (code === 0) {
        clipboard.command = ["bash", "-lc", "wl-copy --type image/gif < " + Util.shellQuote(root.gifOutputPath)]
        clipboard.running = true
      } else root.exporting = false
    }
  }
  Process { id: clipboard; onExited: function(code) { root.exporting = false; if (code === 0) root.close() } }
  Timer { id: frameTimer; interval: 67; repeat: false; onTriggered: root.captureFrame() }

  OverlayWindow {
    id: window
    shown: root.opened
    shownKeyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "omarchy-snap-stickers"

    Rectangle { anchors.fill: parent; color: "#99000000" }
    Rectangle {
      id: card
      width: Math.min(parent.width - 64, 1120)
      height: Math.min(parent.height - 64, 820)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      border.color: Commons.Color.popups.border
      border.width: 1

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(18)
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            text: "Omarchy Snap"
            color: Commons.Color.foreground
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
          }
          Item { width: Math.max(0, parent.width - 425); height: 1 }
          Button { text: "Add GIF…"; onClicked: root.addCustomGif() }
          Button { text: root.exporting ? "Exporting…" : "Save & Copy"; enabled: !root.exporting; onClicked: root.exportImage() }
          Button { text: "×"; onClicked: root.close() }
        }

        Row {
          spacing: 5
          Repeater {
            model: ["🔥", "👀", "✅", "❌", "💀", "🚀"]
            delegate: Button {
              required property string modelData
              text: modelData
              onClicked: root.addEmoji(modelData)
            }
          }
          Repeater {
            model: root.bundledGifs
            delegate: Button {
              required property var modelData
              text: "GIF"
              onClicked: root.addGif(modelData)
            }
          }
          Text {
            text: "Esc to close · drag to move · scroll to resize"
            color: Commons.Color.foreground
            opacity: 0.7
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Item {
          id: previewArea
          width: parent.width
          height: parent.height - 78
          clip: true
          Rectangle { anchors.fill: parent; color: "#151515"; radius: 8 }

          Item {
            id: imageCanvas
            anchors.centerIn: parent
            width: sourceImage.status === Image.Ready ? Math.min(parent.width, parent.height * sourceImage.implicitWidth / sourceImage.implicitHeight) : 0
            height: sourceImage.status === Image.Ready ? Math.min(parent.height, parent.width * sourceImage.implicitHeight / sourceImage.implicitWidth) : 0
            clip: true

            Image {
              id: sourceImage
              anchors.fill: parent
              source: root.imagePath ? Util.fileUrl(root.imagePath) : ""
              asynchronous: true
              cache: false
              fillMode: Image.PreserveAspectFit
            }

            Repeater {
              model: root.emojiItems
              delegate: Text {
                required property var modelData
                required property int index
                x: modelData.x
                y: modelData.y
                text: modelData.text
                font.pixelSize: modelData.size
                textFormat: Text.PlainText
                MouseArea {
                  anchors.fill: parent
                  drag.target: parent
                  onWheel: function(wheel) {
                    var list = root.emojiItems.slice()
                    var item = Object.assign({}, list[index])
                    item.size = Math.max(20, Math.min(180, item.size + (wheel.angleDelta.y > 0 ? 6 : -6)))
                    list[index] = item
                    root.emojiItems = list
                    wheel.accepted = true
                  }
                }
              }
            }

            Repeater {
              model: root.gifItems
              delegate: AnimatedImage {
                required property var modelData
                required property int index
                x: modelData.x
                y: modelData.y
                width: modelData.size
                height: modelData.size
                source: modelData.source
                fillMode: Image.PreserveAspectFit
                playing: root.opened
                MouseArea {
                  anchors.fill: parent
                  drag.target: parent
                  onWheel: function(wheel) {
                    var list = root.gifItems.slice()
                    var item = Object.assign({}, list[index])
                    item.size = Math.max(32, Math.min(320, item.size + (wheel.angleDelta.y > 0 ? 10 : -10)))
                    list[index] = item
                    root.gifItems = list
                    wheel.accepted = true
                  }
                }
              }
            }
          }

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
          }
          Component.onCompleted: forceActiveFocus()
        }
      }
    }
  }
}
