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
  property var selectedSticker: null
  property bool libraryOpen: false
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
  property int framesWritten: 0
  property string captureDir: "/tmp/omarchy-snap-" + Qt.createUuid().toString().replace(/[{}-]/g, "")
  property string gifOutputPath: ""
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
      if (path) root.addGif(path)
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
    onAccepted: root.restoreFromFileDialog(selectedFile)
    onRejected: root.restoreFromFileDialog("")
  }
  Timer { id: fileDialogTimer; interval: 180; repeat: false; onTriggered: customGifDialog.open() }

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
          Item { width: Math.max(0, parent.width - 170); height: 1 }
          Button { text: "×"; onClicked: root.close() }
        }

        Item {
          id: previewArea
          width: parent.width
          height: parent.height - 138
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
                Rectangle {
                  anchors.fill: parent
                  color: "transparent"
                  border.color: Commons.Color.accent
                  border.width: 2
                  radius: 4
                  visible: root.selectedSticker && root.selectedSticker.kind === "emoji" && root.selectedSticker.index === index
                }
                MouseArea {
                  anchors.fill: parent
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
                  border.color: Commons.Color.accent
                  border.width: 2
                  radius: 4
                  visible: root.selectedSticker && root.selectedSticker.kind === "gif" && root.selectedSticker.index === index
                }
                MouseArea {
                  anchors.fill: parent
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

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              if (root.libraryOpen) root.libraryOpen = false
              else root.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
              root.removeSelectedSticker()
              event.accepted = true
            }
          }
          Component.onCompleted: forceActiveFocus()
        }

        Row {
          width: parent.width
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
              text: modelData.label
              onClicked: root.addGif(modelData.source)
            }
          }
          Button { text: "Sticker library"; onClicked: { root.libraryOpen = true; previewArea.forceActiveFocus() } }
          Button { text: "Remove"; enabled: root.selectedSticker !== null; onClicked: root.removeSelectedSticker() }
          Button { text: "Add GIF…"; onClicked: root.addCustomGif() }
          Button { text: root.exporting ? "Saving…" : "Save / Copy"; enabled: !root.exporting; onClicked: root.exportImage() }
          Text {
            text: "Drag stickers · scroll to resize · Esc closes"
            color: Commons.Color.foreground
            opacity: 0.7
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        z: 20
        visible: root.opened && root.libraryOpen
        color: "#99000000"
        MouseArea { anchors.fill: parent; onClicked: root.libraryOpen = false }

        Rectangle {
          id: stickerLibrary
          width: Math.min(parent.width - 40, 640)
          height: Math.min(parent.height - 40, 600)
          anchors.centerIn: parent
          radius: Style.cornerRadius
          color: Commons.Color.popups.background
          border.color: Commons.Color.popups.border
          border.width: 1

          MouseArea { anchors.fill: parent; onClicked: {} }
          Column {
            anchors.fill: parent
            anchors.margins: Style.space(18)
            spacing: Style.space(10)
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
                delegate: Button {
                  required property var modelData
                  width: 72
                  height: 72
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
}
