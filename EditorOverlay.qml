import QtQuick
import QtQuick.Controls
import QtQuick.Controls as Controls
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
  property var selectedSticker: null
  property bool libraryOpen: false
  property string tool: "select"
  property real zoom: 1
  property var strokes: []
  property var redoStrokes: []
  property var activeStroke: []
  property var emojiLibrary: [
    "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "🥹", "😊", "😍", "🥰", "😘", "😎", "🤩", "🥳",
    "😴", "🤔", "🙄", "😬", "😭", "😡", "🤯", "🤡", "👻", "💀", "🤖", "👀", "🙌", "👏", "👍", "👎",
    "👋", "✌️", "🤞", "🙏", "💪", "🫶", "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💔", "💯",
    "🔥", "✨", "⭐", "🌟", "💫", "🎉", "🎊", "🚀", "⚡", "☀️", "🌈", "☁️", "🌙", "🌸", "🌻", "🍀",
    "🍕", "🍔", "🍟", "🌮", "🍩", "🍰", "☕", "🧋", "🍺", "⚽", "🏀", "🎮", "🎵", "🎧", "🎨", "📸",
    "✅", "❌", "❓", "❗", "💡", "💬", "💤", "🎯", "🏆", "💎", "🧿", "🪄", "🪩", "🛸", "🐱", "🐶"
  ]
  property var bundledGifs: [
    { label: "✨", source: Qt.resolvedUrl("assets/sparkle.gif") },
    { label: "🎉", source: Qt.resolvedUrl("assets/party.gif") }
  ]
  property bool exporting: false
  property bool processingSticker: false
  property int framesWritten: 0
  property string captureDir: "/tmp/omarchy-snap-" + Date.now() + "-" + Math.floor(Math.random() * 1000000000)
  property string gifOutputPath: ""
  property string pendingVideoPath: ""
  property string convertedVideoGifPath: ""
  readonly property bool hasAnimatedStickers: gifItems.length > 0

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) } catch (e) { payload = {} }
    var path = String(payload.image || "")
    if (!path || path.length > 4096) return
    if (opened && imagePath === path) return
    imagePath = path
    emojiItems = []
    gifItems = []
    strokes = []
    redoStrokes = []
    zoom = 1
    tool = "select"
    selectedSticker = null
    libraryOpen = false
    opened = true
    Qt.callLater(function() { previewArea.forceActiveFocus() })
  }

  function close() { opened = false; exporting = false }

  function addEmoji(value) {
    if (!imageCanvas.width || !imageCanvas.height) return
    var next = emojiItems.slice()
    next.push({ text: value, x: imageCanvas.width * 0.44, y: imageCanvas.height * 0.4, size: 48 })
    emojiItems = next
    selectedSticker = { kind: "emoji", index: next.length - 1 }
  }

  function addGif(url) {
    if (!url || !imageCanvas.width || !imageCanvas.height) return
    var next = gifItems.slice()
    next.push({ source: String(url), x: imageCanvas.width * 0.42, y: imageCanvas.height * 0.38, size: 112 })
    gifItems = next
    selectedSticker = { kind: "gif", index: next.length - 1 }
  }

  function addCustomGif() {
    libraryOpen = false
    opened = false
    fileDialogTimer.start()
  }

  function restoreFromFileDialog(path) {
    opened = true
    Qt.callLater(function() {
      previewArea.forceActiveFocus()
      if (!path) return
      if (/\.mp4(?:$|[?#])/i.test(String(path))) {
        root.pendingVideoPath = String(path)
        root.convertedVideoGifPath = "/tmp/omarchy-snap-video-" + Date.now() + "-" + Math.floor(Math.random() * 1000000000) + ".gif"
        root.processingSticker = true
        videoToGif.running = true
      } else root.addGif(path)
    })
  }

  function removeSelectedSticker() {
    if (!selectedSticker) return
    if (selectedSticker.kind === "emoji") {
      var emojis = emojiItems.slice()
      emojis.splice(selectedSticker.index, 1)
      emojiItems = emojis
    } else {
      var gifs = gifItems.slice()
      gifs.splice(selectedSticker.index, 1)
      gifItems = gifs
    }
    selectedSticker = null
  }

  function finishStroke() {
    if (!activeStroke || activeStroke.length < 2) { activeStroke = []; return }
    var next = strokes.slice()
    next.push({ points: activeStroke.slice(), erase: tool === "eraser" })
    strokes = next
    redoStrokes = []
    activeStroke = []
    drawing.requestPaint()
  }
  function undo() {
    if (!strokes.length) return
    var next = strokes.slice(); var item = next.pop()
    var redo = redoStrokes.slice(); redo.push(item)
    strokes = next; redoStrokes = redo; drawing.requestPaint()
  }
  function redo() {
    if (!redoStrokes.length) return
    var next = redoStrokes.slice(); var item = next.pop()
    var done = strokes.slice(); done.push(item)
    strokes = done; redoStrokes = next; drawing.requestPaint()
  }
  function clearEdits() {
    emojiItems = []; gifItems = []; selectedSticker = null
    strokes = []; redoStrokes = []; activeStroke = []; drawing.requestPaint()
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
    title: "Add animated sticker or MP4 clip"
    fileMode: FileDialog.OpenFile
    nameFilters: ["Animated images and video (*.gif *.webp *.mp4)"]
    onAccepted: root.restoreFromFileDialog(selectedFile)
    onRejected: root.restoreFromFileDialog("")
  }
  Timer { id: fileDialogTimer; interval: 180; repeat: false; onTriggered: customGifDialog.open() }

  Process {
    id: makeFrameDir
    command: ["mkdir", "-p", root.captureDir, root.outputDir]
    onExited: function(code) { if (code === 0) root.captureFrame(); else root.exporting = false }
  }
  Process {
    id: videoToGif
    command: ["ffmpeg", "-y", "-i", root.pendingVideoPath, "-t", "4", "-an", "-vf", "fps=15,scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse", "-loop", "0", root.convertedVideoGifPath]
    onExited: function(code) {
      root.processingSticker = false
      if (code === 0) root.addGif(root.convertedVideoGifPath)
      else console.warn("Omarchy Snap: could not convert selected MP4 to GIF")
    }
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

    Rectangle { anchors.fill: parent; color: "#d9000000" }
    Rectangle {
      id: card
      width: Math.min(parent.width - 32, 1320)
      height: Math.min(parent.height - 32, 900)
      anchors.centerIn: parent
      radius: 18
      color: "#17191d"
      border.color: "#34373d"
      border.width: 1
      focus: true
      Keys.onPressed: function(event) {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Z) { root.undo(); event.accepted = true }
        else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Y || ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Z))) { root.redo(); event.accepted = true }
        else if (event.key === Qt.Key_Escape) { if (root.libraryOpen) root.libraryOpen = false; else root.close(); event.accepted = true }
        else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) { root.removeSelectedSticker(); event.accepted = true }
      }

      Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        Row {
          width: parent.width
          height: 44
          spacing: 12
          Rectangle { width: 32; height: 32; radius: 10; color: "#d9f99d"; anchors.verticalCenter: parent.verticalCenter
            Text { anchors.centerIn: parent; text: "⌁"; color: "#17220d"; font.pixelSize: 23; font.bold: true }
          }
          Column { anchors.verticalCenter: parent.verticalCenter; spacing: 1
            Text { text: "Snap Studio"; color: "#f4f4f5"; font.pixelSize: 15; font.weight: Font.DemiBold; textFormat: Text.PlainText }
            Text { text: "SCREENSHOT EDITOR"; color: "#858991"; font.pixelSize: 9; font.letterSpacing: 1.5; textFormat: Text.PlainText }
          }
          Item { width: Math.max(0, parent.width - 260); height: 1 }
          Text { text: root.imagePath.split("/").pop(); color: "#a1a1aa"; elide: Text.ElideMiddle; width: 220; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; textFormat: Text.PlainText }
          Button { text: "×"; ToolTip.visible: hovered; ToolTip.text: "Close · Esc"; onClicked: root.close() }
        }

        Item {
          id: previewArea
          width: parent.width
          height: parent.height - 150
          clip: true
          Rectangle { anchors.fill: parent; color: "#101114"; radius: 13; border.color: "#292c32"; border.width: 1 }
          Grid { anchors.fill: parent; anchors.margins: 1; columns: Math.ceil(parent.width / 28); spacing: 0; opacity: 0.18
            Repeater { model: Math.ceil(parent.width / 28) * Math.ceil(parent.height / 28); delegate: Rectangle { required property int index; width: 28; height: 28; color: ((Math.floor(index / Math.ceil(previewArea.width / 28)) + index % Math.ceil(previewArea.width / 28)) % 2) ? "#17191d" : "#202227" } }
          }

          Item {
            id: imageCanvas
            anchors.centerIn: parent
            width: sourceImage.status === Image.Ready ? Math.min(parent.width - 40, (parent.height - 40) * sourceImage.implicitWidth / Math.max(1, sourceImage.implicitHeight)) * root.zoom : 0
            height: sourceImage.status === Image.Ready ? Math.min(parent.height - 40, (parent.width - 40) * sourceImage.implicitHeight / Math.max(1, sourceImage.implicitWidth)) * root.zoom : 0
            clip: true
            Behavior on width { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }

            Image {
              id: sourceImage
              anchors.fill: parent
              source: root.imagePath ? Util.fileUrl(root.imagePath) : ""
              asynchronous: true
              cache: false
              fillMode: Image.PreserveAspectFit
            }

            Canvas {
              id: drawing
              anchors.fill: parent
              renderTarget: Canvas.Image
              onPaint: {
                var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                function draw(stroke) {
                  if (!stroke || stroke.points.length < 2) return
                  ctx.save(); ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.lineWidth = stroke.erase ? 24 : 5
                  ctx.globalCompositeOperation = stroke.erase ? "destination-out" : "source-over"; ctx.strokeStyle = "#d9f99d"
                  ctx.beginPath(); ctx.moveTo(stroke.points[0].x, stroke.points[0].y)
                  for (var p = 1; p < stroke.points.length; p++) ctx.lineTo(stroke.points[p].x, stroke.points[p].y)
                  ctx.stroke(); ctx.restore()
                }
                for (var i = 0; i < root.strokes.length; i++) draw(root.strokes[i])
                draw({ points: root.activeStroke, erase: root.tool === "eraser" })
              }
              MouseArea {
                anchors.fill: parent
                enabled: root.tool === "brush" || root.tool === "eraser"
                onPressed: function(mouse) { root.selectedSticker = null; root.activeStroke = [{ x: mouse.x, y: mouse.y }]; drawing.requestPaint() }
                onPositionChanged: function(mouse) { if (pressed) { var points = root.activeStroke.slice(); points.push({ x: mouse.x, y: mouse.y }); root.activeStroke = points; drawing.requestPaint() } }
                onReleased: root.finishStroke()
              }
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
                Rectangle {
                  anchors.fill: parent
                  color: "transparent"
                  border.color: "#d9f99d"
                  border.width: 1
                  radius: 5
                  visible: root.selectedSticker && root.selectedSticker.kind === "emoji" && root.selectedSticker.index === index
                }
                MouseArea {
                  anchors.fill: parent
                  enabled: root.tool === "select"
                  drag.target: parent
                  onPressed: root.selectedSticker = { kind: "emoji", index: index }
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
                Rectangle {
                  anchors.fill: parent
                  color: "transparent"
                border.color: "#d9f99d"
                border.width: 1
                radius: 5
                  visible: root.selectedSticker && root.selectedSticker.kind === "gif" && root.selectedSticker.index === index
                }
                MouseArea {
                  anchors.fill: parent
                  enabled: root.tool === "select"
                  drag.target: parent
                  onPressed: root.selectedSticker = { kind: "gif", index: index }
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

          Component.onCompleted: forceActiveFocus()
        }

        Row {
          width: parent.width
          height: 54
          spacing: 8
          Rectangle { width: parent.width - 240; height: 50; radius: 12; color: "#202227"; border.color: "#34373d"; anchors.verticalCenter: parent.verticalCenter
            Row { anchors.centerIn: parent; spacing: 4
              ToolButton { label: "↖"; hint: "Select and move"; active: root.tool === "select"; onClicked: root.tool = "select" }
              ToolButton { label: "✎"; hint: "Brush"; active: root.tool === "brush"; onClicked: root.tool = "brush" }
              ToolButton { label: "⌫"; hint: "Eraser"; active: root.tool === "eraser"; onClicked: root.tool = "eraser" }
              Rectangle { width: 1; height: 22; color: "#3a3d43"; anchors.verticalCenter: parent.verticalCenter }
              ToolButton { label: "↶"; hint: "Undo · Ctrl+Z"; active: false; enabled: root.strokes.length > 0; onClicked: root.undo() }
              ToolButton { label: "↷"; hint: "Redo · Ctrl+Y"; active: false; enabled: root.redoStrokes.length > 0; onClicked: root.redo() }
              ToolButton { label: "▧"; hint: "Stickers"; active: root.libraryOpen; onClicked: root.libraryOpen = true }
              ToolButton { label: "＋"; hint: "Add GIF or MP4"; active: false; onClicked: root.addCustomGif() }
              Rectangle { width: 1; height: 22; color: "#3a3d43"; anchors.verticalCenter: parent.verticalCenter }
              ToolButton { label: "−"; hint: "Zoom out"; active: false; onClicked: root.zoom = Math.max(0.5, root.zoom - 0.1) }
              Text { text: Math.round(root.zoom * 100) + "%"; width: 42; color: "#c4c6cb"; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 11; textFormat: Text.PlainText }
              ToolButton { label: "＋"; hint: "Zoom in"; active: false; onClicked: root.zoom = Math.min(1.5, root.zoom + 0.1) }
            }
          }
          Button { text: "Clear"; onClicked: root.clearEdits(); anchors.verticalCenter: parent.verticalCenter }
          Button { text: root.processingSticker ? "Preparing…" : (root.exporting ? "Exporting…" : "Export  ↗"); enabled: !root.exporting && !root.processingSticker; onClicked: root.exportImage(); anchors.verticalCenter: parent.verticalCenter }
        }
      }

      Rectangle {
        anchors.fill: parent
        z: 20
        visible: root.opened && root.libraryOpen
        color: "#b8000000"
        MouseArea { anchors.fill: parent; onClicked: root.libraryOpen = false }

        Rectangle {
          id: stickerLibrary
          width: Math.min(parent.width - 40, 640)
          height: Math.min(parent.height - 40, 600)
          anchors.centerIn: parent
          radius: 16
          color: "#1b1d21"
          border.color: "#3b3e44"
          border.width: 1

          MouseArea { anchors.fill: parent; onClicked: {} }
          Column {
            anchors.fill: parent
            anchors.margins: Style.space(18)
            spacing: 12
            Row {
              width: parent.width
              Text {
                text: "Sticker library"
                color: Commons.Color.foreground
                font.pixelSize: Style.font.title
                font.weight: Font.DemiBold
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
              }
              Item { width: Math.max(0, parent.width - 230); height: 1 }
              Button { text: "Close"; onClicked: root.libraryOpen = false }
            }
            Text { text: "Emoji"; color: Commons.Color.foreground; font.weight: Font.DemiBold; textFormat: Text.PlainText }
            GridView {
              id: emojiGrid
              width: parent.width
              height: 310
              cellWidth: 58
              cellHeight: 58
              clip: true
              model: root.emojiLibrary
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
              delegate: Button {
                required property string modelData
                width: 48
                height: 48
                text: modelData
                onClicked: { root.addEmoji(modelData); root.libraryOpen = false }
              }
            }
            Text { text: "Animated GIF stickers"; color: Commons.Color.foreground; font.weight: Font.DemiBold; textFormat: Text.PlainText }
            Row {
              spacing: Style.space(10)
              Repeater {
                model: root.bundledGifs
                delegate: Controls.Button {
                  required property var modelData
                  width: 72
                  height: 72
                  background: Rectangle {
                    radius: Style.cornerRadius
                    color: Commons.Color.popups.background
                    border.color: Commons.Color.popups.border
                    border.width: 1
                  }
                  contentItem: AnimatedImage {
                    source: modelData.source
                    fillMode: Image.PreserveAspectFit
                    playing: root.opened && root.libraryOpen
                  }
                  onClicked: { root.addGif(modelData.source); root.libraryOpen = false }
                }
              }
              Button { text: "Add custom…"; onClicked: root.addCustomGif() }
            }
          }
        }
      }
    }
  }

  component ToolButton: Button {
    property string label: ""
    property string hint: ""
    property bool active: false
    width: 38; height: 38
    text: label
    ToolTip.visible: hovered
    ToolTip.text: hint
    background: Rectangle { radius: 8; color: active ? "#383e31" : (parent.hovered ? "#303238" : "transparent"); border.color: active ? "#71834e" : "transparent"; border.width: 1 }
    contentItem: Text { text: parent.text; color: parent.active ? "#d9f99d" : (parent.enabled ? "#d4d4d8" : "#62646b"); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; textFormat: Text.PlainText }
  }
}
