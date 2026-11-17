import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Omarchy Snap — sticker + markup editor.
//
// Hyprland layer rule: blur, omarchy-snap-stickers (configured in looknfeel.lua).
//
// Shortcuts: V select · B brush · E eraser · [ ] brush size · Ctrl+Z / Ctrl+Shift+Z undo/redo
//            Ctrl+K sticker library · Ctrl+S export · Del remove · R / Shift+R rotate
//            + − 0 zoom · Ctrl+scroll zoom · middle-drag pan · Esc back/close
Item {
  id: root

  // ───────────────────────── Public state (unchanged API) ─────────────────────────
  property bool opened: false
  property string imagePath: ""
  property string outputDir: Quickshell.env("HOME") + "/Pictures/Screenshots"
  property var emojiItems: []
  property var gifItems: []
  property var selectedSticker: null
  property bool libraryOpen: false
  property bool exporting: false
  property bool processingSticker: false
  property int framesWritten: 0
  property string captureDir: "/tmp/omarchy-snap-" + Date.now() + "-" + Math.floor(Math.random() * 1000000000)
  property string gifOutputPath: ""
  property string pendingVideoPath: ""
  property string convertedVideoGifPath: ""
  readonly property bool hasAnimatedStickers: gifItems.length > 0
  property var gifLoadStatus: ({})
  property double gifLoadWaitStarted: 0
  readonly property bool animatedStickersReady: {
    for (var i = 0; i < gifItems.length; i++)
      if (gifLoadStatus[gifItems[i].source] !== Image.Ready) return false
    return true
  }
  readonly property bool animatedStickerLoadFailed: {
    for (var i = 0; i < gifItems.length; i++)
      if (gifLoadStatus[gifItems[i].source] === Image.Error) return true
    return false
  }

  // ───────────────────────── Sticker catalogue ─────────────────────────
  property var emojiCatalog: [
    { cat: "Faces", list: [
      "😀 grin happy", "😃 smile happy", "😄 joy smile", "😁 beam grin", "😆 laugh", "😅 sweat nervous", "😂 lol tears", "🤣 rofl laughing",
      "🥹 touched grateful", "😊 blush", "😍 love heart eyes", "🥰 adore love", "😘 kiss", "😎 cool sunglasses", "🤩 star struck wow", "🥳 party celebrate",
      "😴 sleep tired", "🤔 think hmm", "🙄 eyeroll", "😬 grimace awkward", "😭 cry sad", "😡 angry mad", "🤯 mind blown", "🤡 clown",
      "👻 ghost", "💀 skull dead", "🤖 robot", "👀 eyes look" ] },
    { cat: "Gestures", list: [
      "🙌 hooray praise", "👏 clap applause", "👍 thumbs up like", "👎 thumbs down dislike", "👋 wave hello", "✌️ peace victory",
      "🤞 fingers crossed luck", "🙏 pray thanks please", "💪 strong flex", "🫶 heart hands" ] },
    { cat: "Hearts", list: [
      "❤️ red heart love", "🧡 orange heart", "💛 yellow heart", "💚 green heart", "💙 blue heart", "💜 purple heart",
      "🖤 black heart", "🤍 white heart", "💔 broken heart", "💯 hundred perfect" ] },
    { cat: "Nature", list: [
      "🔥 fire hot lit", "✨ sparkles magic", "⭐ star", "🌟 glowing star", "💫 dizzy", "🎉 party popper", "🎊 confetti", "🚀 rocket launch",
      "⚡ lightning bolt", "☀️ sun", "🌈 rainbow", "☁️ cloud", "🌙 moon night", "🌸 blossom flower", "🌻 sunflower", "🍀 clover luck" ] },
    { cat: "Fun", list: [
      "🍕 pizza", "🍔 burger", "🍟 fries", "🌮 taco", "🍩 donut", "🍰 cake", "☕ coffee", "🧋 boba tea",
      "🍺 beer", "⚽ soccer football", "🏀 basketball", "🎮 game controller", "🎵 music note", "🎧 headphones", "🎨 art palette", "📸 camera photo" ] },
    { cat: "Symbols", list: [
      "✅ check done", "❌ cross wrong", "❓ question", "❗ exclamation alert", "💡 idea bulb", "💬 chat speech", "💤 zzz sleep", "🎯 target bullseye",
      "🏆 trophy win", "💎 gem diamond", "🧿 nazar evil eye", "🪄 magic wand", "🪩 disco ball", "🛸 ufo", "🐱 cat", "🐶 dog" ] }
  ]
  property var emojiLibrary: {
    var flat = []
    for (var i = 0; i < emojiCatalog.length; i++)
      for (var j = 0; j < emojiCatalog[i].list.length; j++) {
        var s = emojiCatalog[i].list[j]
        flat.push(s.slice(0, s.indexOf(" ")))
      }
    return flat
  }
  property var bundledGifs: [
    { label: "✨", name: "sparkle shine", source: Qt.resolvedUrl("assets/sparkle.gif") },
    { label: "🎉", name: "party celebrate", source: Qt.resolvedUrl("assets/party.gif") }
  ]
  property var customGifs: []
  readonly property var quickEmoji: ["🔥", "👀", "✅", "❌", "💀", "🚀"]
  readonly property var libraryCategories: ["All", "Emojis", "Faces", "Gestures", "Hearts", "Nature", "Fun", "Symbols", "Animated", "Custom"]

  // ───────────────────────── Editor state ─────────────────────────
  property string tool: "select"          // select | draw | erase
  property color brushColor: "#ff4d4f"
  property int brushSize: 6               // on-screen px
  property var strokes: []                // { color, size, erase, pts:[{x,y}] } in image px
  property var undoStack: []
  property var redoStack: []
  property real zoom: 1.0
  property real panX: 0
  property real panY: 0
  property var ctxMenu: null
  property string libraryQuery: ""
  property string libraryCategory: "All"
  property string libraryHover: ""
  property real lastCoalesce: 0

  // Right-docked export panel
  property bool exportDialogOpen: false
  readonly property string sidebarMode: libraryOpen ? "library" : (exportDialogOpen ? "export" : "closed")
  property string exportFormat: "png"     // png | gif | mp4
  property string exportState: "idle"     // idle | working | done | error
  property string exportMessage: ""
  property real exportProgress: 0
  property string lastOutputPath: ""
  property real exportScale: 1
  property real exportQuality: 85

  // ───────────────────────── Derived ─────────────────────────
  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color glassSurface: Qt.rgba(0.035, 0.04, 0.045, 0.52)
  property string tooltipText: ""
  property real tooltipX: 0
  property real tooltipY: 0
  property bool tooltipBelow: false
  // Avoid the `onX` prefix: QML parses it as a signal handler name.
  readonly property color accentForeground: "#0b0b0c"
  readonly property int smallFontPx: 12
  readonly property int mediumFontPx: 13
  readonly property int tinyFontPx: 8
  readonly property bool compact: card.width < 860
  readonly property real imgW: sourceImage.status === Image.Ready ? sourceImage.implicitWidth : 0
  readonly property real imgH: sourceImage.status === Image.Ready ? sourceImage.implicitHeight : 0
  readonly property real fitScale: (imgW > 0 && stage.width > 0 && stage.height > 0)
    ? Math.max(0.02, Math.min(2, Math.min((stage.width - 56) / imgW, (stage.height - 40) / imgH))) : 1
  readonly property real viewScale: fitScale * zoom
  readonly property bool viewIsFitted: Math.abs(zoom - 1) < 0.001 && Math.abs(panX) < 0.01 && Math.abs(panY) < 0.01
  readonly property var selectedItem: {
    if (!selectedSticker) return null
    var list = selectedSticker.kind === "emoji" ? emojiItems : gifItems
    return list[selectedSticker.index] || null
  }
  readonly property bool drawMode: tool !== "select"
  readonly property bool hasContent: emojiItems.length > 0 || gifItems.length > 0 || strokes.length > 0
  readonly property var libraryModel: buildLibrary(libraryQuery, libraryCategory, customGifs)
  readonly property string fileName: imagePath ? imagePath.split("/").pop() : ""

  function alphaOf(c, v) { return Qt.rgba(c.r, c.g, c.b, v) }
  function showTooltip(button) {
    if (!button.tip) return
    var point = button.mapToItem(window, button.width / 2, button.tipBelow ? button.height + 8 : -8)
    tooltipText = button.tip
    tooltipX = point.x
    tooltipY = point.y
    tooltipBelow = button.tipBelow
  }
  function hideTooltip() { tooltipText = "" }
  function recordGifLoad(source, status) {
    if (!source) return
    var next = Object.assign({}, gifLoadStatus)
    next[String(source)] = status
    gifLoadStatus = next
  }

  // ───────────────────────── Lifecycle ─────────────────────────
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
    undoStack = []
    redoStack = []
    selectedSticker = null
    ctxMenu = null
    libraryOpen = false
    exportDialogOpen = false
    exportState = "idle"
    tool = "select"
    zoom = 1; panX = 0; panY = 0
    opened = true
    Qt.callLater(function() { card.forceActiveFocus() })
  }

  function close() { opened = false; exporting = false; exportDialogOpen = false; ctxMenu = null; hideTooltip() }

  function escapePressed() {
    if (ctxMenu) ctxMenu = null
    else if (exportDialogOpen) { if (!exporting) exportDialogOpen = false }
    else if (searchInput.activeFocus) { searchInput.focus = false; card.forceActiveFocus() }
    else if (libraryOpen) libraryOpen = false
    else if (selectedSticker) selectedSticker = null
    else close()
  }

  // ───────────────────────── History ─────────────────────────
  function snapshot() { return JSON.stringify({ e: emojiItems, g: gifItems, s: strokes }) }
  function pushHistory(snap) {
    var u = undoStack.concat([snap])
    if (u.length > 40) u = u.slice(u.length - 40)
    undoStack = u
    redoStack = []
  }
  function commit() { pushHistory(snapshot()) }
  function commitCoalesced() {
    var now = Date.now()
    if (now - lastCoalesce > 700) commit()
    lastCoalesce = now
  }
  function restore(json) {
    var d = JSON.parse(json)
    emojiItems = d.e
    gifItems = d.g
    strokes = d.s
    selectedSticker = null
    strokeCanvas.requestPaint()
  }
  function undo() {
    if (undoStack.length === 0) return
    var u = undoStack.slice()
    var s = u.pop()
    redoStack = redoStack.concat([snapshot()])
    undoStack = u
    restore(s)
  }
  function redo() {
    if (redoStack.length === 0) return
    var r = redoStack.slice()
    var s = r.pop()
    undoStack = undoStack.concat([snapshot()])
    redoStack = r
    restore(s)
  }
  function clearCanvas() {
    if (!hasContent) return
    commit()
    emojiItems = []
    gifItems = []
    strokes = []
    selectedSticker = null
    strokeCanvas.requestPaint()
  }

  // ───────────────────────── Tools / view ─────────────────────────
  function setTool(t) {
    tool = t
    if (t !== "select") selectedSticker = null
    ctxMenu = null
    card.forceActiveFocus()
  }
  function zoomBy(f) { zoom = Math.max(0.25, Math.min(8, zoom * f)); if (zoom <= 1.001) { panX = 0; panY = 0 } }
  function fitView() { zoom = 1; panX = 0; panY = 0 }

  // ───────────────────────── Stickers ─────────────────────────
  function getSticker(kind, index) { return (kind === "emoji" ? emojiItems : gifItems)[index] }

  function updateSticker(kind, index, props) {
    var list = (kind === "emoji" ? emojiItems : gifItems).slice()
    var item = Object.assign({}, list[index])
    for (var k in props) item[k] = props[k]
    list[index] = item
    if (kind === "emoji") emojiItems = list
    else gifItems = list
  }

  function addEmoji(value) {
    if (!imgW || !imgH) return
    commit()
    var next = emojiItems.slice()
    next.push({ text: value, x: imgW * 0.44, y: imgH * 0.4, size: Math.round(56 / viewScale), rotation: 0 })
    emojiItems = next
    selectedSticker = { kind: "emoji", index: next.length - 1 }
    tool = "select"
  }

  function addGif(url, remember) {
    if (!url || !imgW || !imgH) return
    commit()
    var next = gifItems.slice()
    next.push({ source: String(url), x: imgW * 0.42, y: imgH * 0.38, size: Math.round(120 / viewScale), rotation: 0 })
    gifItems = next
    selectedSticker = { kind: "gif", index: next.length - 1 }
    tool = "select"
    if (remember) {
      var src = String(url)
      var known = false
      for (var i = 0; i < customGifs.length; i++) if (customGifs[i].source === src) known = true
      if (!known) {
        var nm = decodeURIComponent(src.split("/").pop().split("?")[0])
        customGifs = customGifs.concat([{ label: "GIF", name: nm, source: src }])
      }
    }
  }

  function addCustomGif() {
    libraryOpen = false
    opened = false
    fileDialogTimer.target = "gif"
    fileDialogTimer.start()
  }

  function openGifLibrary() {
    exportDialogOpen = false
    libraryCategory = "Animated"
    libraryQuery = ""
    searchInput.text = ""
    libraryHover = ""
    libraryOpen = true
    card.forceActiveFocus()
  }

  function openEmojiLibrary() {
    exportDialogOpen = false
    libraryCategory = "Emojis"
    libraryQuery = ""
    searchInput.text = ""
    libraryHover = ""
    libraryOpen = true
    card.forceActiveFocus()
  }

  function openImageDialog() {
    libraryOpen = false
    opened = false
    fileDialogTimer.target = "image"
    fileDialogTimer.start()
  }

  function restoreFromFileDialog(path) {
    opened = true
    Qt.callLater(function() {
      card.forceActiveFocus()
      if (!path) return
      if (/\.mp4(?:$|[?#])/i.test(String(path))) {
        root.pendingVideoPath = String(path)
        root.convertedVideoGifPath = "/tmp/omarchy-snap-video-" + Date.now() + "-" + Math.floor(Math.random() * 1000000000) + ".gif"
        root.processingSticker = true
        videoToGif.running = true
      } else root.addGif(path, true)
    })
  }

  function restoreFromImageDialog(url) {
    opened = true
    Qt.callLater(function() {
      card.forceActiveFocus()
      if (!url) return
      var p = decodeURIComponent(String(url).replace(/^file:\/\//, ""))
      if (!p || p.length > 4096) return
      imagePath = p
      emojiItems = []; gifItems = []; strokes = []
      undoStack = []; redoStack = []
      selectedSticker = null
      zoom = 1; panX = 0; panY = 0
      strokeCanvas.requestPaint()
    })
  }

  function removeSelectedSticker() {
    if (!selectedSticker) return
    commit()
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

  function duplicateSelected() {
    if (!selectedSticker) return
    commit()
    var kind = selectedSticker.kind
    var copy = Object.assign({}, getSticker(kind, selectedSticker.index))
    copy.x += 28; copy.y += 28
    var list = (kind === "emoji" ? emojiItems : gifItems).concat([copy])
    if (kind === "emoji") emojiItems = list
    else gifItems = list
    selectedSticker = { kind: kind, index: list.length - 1 }
  }

  function bringToFront() {
    if (!selectedSticker) return
    commit()
    var kind = selectedSticker.kind
    var list = (kind === "emoji" ? emojiItems : gifItems).slice()
    var it = list.splice(selectedSticker.index, 1)[0]
    list.push(it)
    if (kind === "emoji") emojiItems = list
    else gifItems = list
    selectedSticker = { kind: kind, index: list.length - 1 }
  }

  function rotateSelected(deg) {
    if (!selectedSticker || !selectedItem) return
    commitCoalesced()
    updateSticker(selectedSticker.kind, selectedSticker.index, { rotation: ((selectedItem.rotation || 0) + deg) % 360 })
  }

  function buildLibrary(query, cat, customs) {
    var q = String(query || "").trim().toLowerCase()
    var out = []
    var gifs = bundledGifs.map(function(g) { return { kind: "gif", source: String(g.source), name: g.name || g.label, label: g.label, cat: "Animated" } })
      .concat(customs.map(function(g) { return { kind: "gif", source: g.source, name: g.name, label: g.label, cat: "Custom" } }))
    for (var i = 0; i < gifs.length; i++) {
      var g = gifs[i]
      var catOk = cat === "All" || cat === g.cat || (cat === "Animated" && g.cat === "Custom")
      if (catOk && (!q || g.name.toLowerCase().indexOf(q) >= 0 || "gif animated".indexOf(q) >= 0)) out.push(g)
    }
    for (var a = 0; a < emojiCatalog.length; a++) {
      var grp = emojiCatalog[a]
      if (cat !== "All" && cat !== "Emojis" && cat !== grp.cat) continue
      for (var b = 0; b < grp.list.length; b++) {
        var s = grp.list[b]
        var sp = s.indexOf(" ")
        var kw = s.slice(sp + 1)
        if (q && kw.toLowerCase().indexOf(q) < 0 && grp.cat.toLowerCase().indexOf(q) < 0) continue
        out.push({ kind: "emoji", text: s.slice(0, sp), name: kw, cat: grp.cat })
      }
    }
    return out
  }

  function isActiveCell(m) {
    if (!selectedSticker || !selectedItem || selectedSticker.kind !== m.kind) return false
    return m.kind === "emoji" ? selectedItem.text === m.text : selectedItem.source === m.source
  }

  // ───────────────────────── Export ─────────────────────────
  function exportImage() {
    if (exporting || !opened || sourceImage.status !== Image.Ready) return
    libraryOpen = false
    exportFormat = hasAnimatedStickers ? "gif" : "png"
    exportState = "idle"
    exportMessage = ""
    exportProgress = 0
    exportDialogOpen = true
  }

  function startExport() {
    if (exporting || sourceImage.status !== Image.Ready) return
    if (exportFormat !== "png" && !hasAnimatedStickers) exportFormat = "png"
    if (exportFormat !== "png" && !animatedStickersReady) {
      if (animatedStickerLoadFailed) { exportState = "error"; exportMessage = "An animated sticker could not be loaded."; return }
      if (!gifLoadWaitStarted) gifLoadWaitStarted = Date.now()
      exportState = "working"
      exportMessage = "Loading animated stickers…"
      gifLoadTimer.start()
      return
    }
    gifLoadWaitStarted = 0
    exporting = true
    selectedSticker = null
    exportState = "working"
    exportMessage = "Preparing…"
    exportProgress = 0.02
    framesWritten = 0
    var base = outputDir + "/omarchy-snap-" + Date.now()
    lastOutputPath = base + "." + exportFormat
    gifOutputPath = lastOutputPath
    exportScale = exportFormat === "png" ? 1 : Math.min(1, 1280 / Math.max(imgW, imgH))
    var quality = Math.max(50, Math.min(100, Math.round(exportQuality)))
    var gifColors = Math.round(64 + (quality - 50) * 3.84)
    var mp4Crf = Math.round(35 - (quality - 50) * 0.34)
    encodeGif.command = ["ffmpeg", "-y", "-framerate", "15", "-i", captureDir + "/frame-%03d.png", "-loop", "0", "-vf", "split[s0][s1];[s0]palettegen=max_colors=" + gifColors + "[p];[s1][p]paletteuse", gifOutputPath]
    encodeMp4.command = ["ffmpeg", "-y", "-framerate", "15", "-i", captureDir + "/frame-%03d.png", "-c:v", "libx264", "-crf", String(mp4Crf), "-pix_fmt", "yuv420p", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-movflags", "+faststart", lastOutputPath]
    makeFrameDir.running = true
  }

  function exportFailed(msg) {
    exporting = false
    exportState = "error"
    exportMessage = msg
    cleanup.running = true
  }

  function copyExport() {
    if (!lastOutputPath || copyExportProc.running) return
    var mimeType = exportFormat === "png" ? "image/png" : (exportFormat === "gif" ? "image/gif" : "video/mp4")
    exportMessage = "Copying exported file…"
    copyExportProc.command = ["bash", "-lc", "wl-copy --type " + mimeType + " < " + Util.shellQuote(lastOutputPath)]
    copyExportProc.running = true
  }

  function grabSize() { return Qt.size(Math.max(2, Math.round(imgW * exportScale)), Math.max(2, Math.round(imgH * exportScale))) }

  function savePng() {
    exportMessage = "Rendering image…"
    imageCanvas.grabToImage(function(result) {
      if (!result.saveToFile(root.lastOutputPath)) { root.exportFailed("Could not write the image file."); return }
      root.exportProgress = 0.8
      root.exportMessage = "Copying to clipboard…"
      clipboard.command = ["bash", "-lc", "wl-copy --type image/png < " + Util.shellQuote(root.lastOutputPath)]
      clipboard.running = true
    }, grabSize())
  }

  function captureFrame() {
    if (framesWritten >= 38) {
      exportProgress = 0.8
      exportMessage = exportFormat === "mp4" ? "Encoding MP4…" : "Encoding GIF…"
      if (exportFormat === "mp4") encodeMp4.running = true
      else encodeGif.running = true
      return
    }
    var frame = framesWritten
    exportMessage = "Capturing frame " + (frame + 1) + " of 38"
    imageCanvas.grabToImage(function(result) {
      var path = root.captureDir + "/frame-" + ("000" + frame).slice(-3) + ".png"
      if (!result.saveToFile(path)) { root.exportFailed("Could not write a capture frame."); return }
      root.framesWritten = frame + 1
      root.exportProgress = 0.05 + 0.75 * (root.framesWritten / 38)
      frameTimer.start()
    }, grabSize())
  }

  // ───────────────────────── Dialogs & processes ─────────────────────────
  FileDialog {
    id: customGifDialog
    title: "Add animated sticker or MP4 clip"
    fileMode: FileDialog.OpenFile
    nameFilters: ["Animated images and video (*.gif *.webp *.mp4)"]
    onAccepted: root.restoreFromFileDialog(selectedFile)
    onRejected: root.restoreFromFileDialog("")
  }
  FileDialog {
    id: imageDialog
    title: "Open screenshot"
    fileMode: FileDialog.OpenFile
    nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp)"]
    onAccepted: root.restoreFromImageDialog(selectedFile)
    onRejected: root.restoreFromImageDialog("")
  }
  Timer {
    id: fileDialogTimer
    property string target: "gif"
    interval: 180; repeat: false
    onTriggered: { if (target === "image") imageDialog.open(); else customGifDialog.open() }
  }

  Process {
    id: makeFrameDir
    command: ["mkdir", "-p", root.captureDir, root.outputDir]
    onExited: function(code) {
      if (code !== 0) { root.exportFailed("Could not create the output folder."); return }
      if (root.exportFormat === "png") root.savePng()
      else root.captureFrame()
    }
  }
  Process {
    id: videoToGif
    command: ["ffmpeg", "-y", "-i", root.pendingVideoPath, "-t", "4", "-an", "-vf", "fps=15,scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse", "-loop", "0", root.convertedVideoGifPath]
    onExited: function(code) {
      root.processingSticker = false
      if (code === 0) root.addGif(root.convertedVideoGifPath, true)
      else console.warn("Omarchy Snap: could not convert selected MP4 to GIF")
    }
  }
  Process {
    id: encodeGif
    command: ["ffmpeg", "-y", "-framerate", "15", "-i", root.captureDir + "/frame-%03d.png", "-loop", "0", "-vf", "split[s0][s1];[s0]palettegen=max_colors=192[p];[s1][p]paletteuse", root.gifOutputPath]
    onExited: function(code) {
      if (code === 0) {
        root.exportProgress = 0.92
        root.exportMessage = "Copying to clipboard…"
        clipboard.command = ["bash", "-lc", "wl-copy --type image/gif < " + Util.shellQuote(root.gifOutputPath)]
        clipboard.running = true
      } else root.exportFailed("FFmpeg could not encode the GIF.")
    }
  }
  Process {
    id: encodeMp4
    command: ["ffmpeg", "-y", "-framerate", "15", "-i", root.captureDir + "/frame-%03d.png", "-c:v", "libx264", "-crf", "23", "-pix_fmt", "yuv420p", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-movflags", "+faststart", root.lastOutputPath]
    onExited: function(code) {
      if (code === 0) {
        root.exportProgress = 0.92
        root.exportMessage = "Copying file path…"
        clipboard.command = ["bash", "-lc", "printf %s " + Util.shellQuote(root.lastOutputPath) + " | wl-copy"]
        clipboard.running = true
      } else root.exportFailed("FFmpeg could not encode the MP4 (is libx264 available?).")
    }
  }
  Process {
    id: clipboard
    onExited: function(code) {
      root.exporting = false
      cleanup.running = true
      if (code === 0) {
        root.exportState = "done"
        root.exportProgress = 1
        root.exportMessage = root.exportFormat === "mp4" ? "Saved. File path copied to clipboard." : "Saved and copied to clipboard."
      } else {
        root.exportState = "error"
        root.exportMessage = "Saved to disk, but copying to the clipboard failed."
      }
    }
  }
  Process {
    id: copyPathProc
    command: ["bash", "-lc", "printf %s " + Util.shellQuote(root.lastOutputPath) + " | wl-copy"]
  }
  Process {
    id: copyExportProc
    onExited: function(code) {
      root.exportMessage = code === 0 ? "Export copied to clipboard." : "Could not copy the exported file to the clipboard."
    }
  }
  Process {
    id: openFolderProc
    command: ["xdg-open", root.outputDir]
  }
  Process {
    id: cleanup
    command: ["rm", "-rf", root.captureDir]
  }
  Timer { id: frameTimer; interval: 67; repeat: false; onTriggered: root.captureFrame() }
  Timer {
    id: gifLoadTimer
    interval: 100
    repeat: true
    onTriggered: {
      if (!root.exportDialogOpen) { stop(); root.gifLoadWaitStarted = 0; return }
      if (root.animatedStickerLoadFailed) {
        stop(); root.gifLoadWaitStarted = 0
        root.exportState = "error"
        root.exportMessage = "An animated sticker could not be loaded."
      } else if (root.animatedStickersReady) {
        stop(); root.gifLoadWaitStarted = 0
        root.startExport()
      } else if (Date.now() - root.gifLoadWaitStarted > 15000) {
        stop(); root.gifLoadWaitStarted = 0
        root.exportState = "error"
        root.exportMessage = "Timed out while loading an animated sticker."
      }
    }
  }

  // ───────────────────────── Inline components ─────────────────────────
  component Icon: Canvas {
    id: ic
    property string name: ""
    property color col: "white"
    property bool flip: false
    width: 18
    height: 18
    onColChanged: requestPaint()
    onNameChanged: requestPaint()
    onFlipChanged: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      ctx.save()
      ctx.scale(width / 24, height / 24)
      if (flip) { ctx.translate(24, 0); ctx.scale(-1, 1) }
      ctx.shadowColor = "#99000000"
      ctx.shadowBlur = 3
      ctx.shadowOffsetX = 0
      ctx.shadowOffsetY = 0
      ctx.strokeStyle = col
      ctx.fillStyle = col
      ctx.lineWidth = 1.8
      ctx.lineCap = "round"
      ctx.lineJoin = "round"
      ctx.beginPath()
      var M = function(x, y) { ctx.moveTo(x, y) }
      var L = function(x, y) { ctx.lineTo(x, y) }
      var C = function(cx, cy, r) { ctx.moveTo(cx + r, cy); ctx.arc(cx, cy, r, 0, Math.PI * 2) }
      switch (name) {
      case "select":
        M(5, 3); L(5, 18); L(9, 14.5); L(12, 21); L(14.5, 20); L(11.7, 13.5); L(17, 13); ctx.closePath(); break
      case "brush":
        M(4, 20); L(5, 15); L(16, 4); L(20, 8); L(9, 19); ctx.closePath(); M(13, 7); L(17, 11); break
      case "eraser":
        M(3.5, 16); L(13, 6.5); L(18.5, 12); L(11, 19.5); L(7, 19.5); ctx.closePath(); M(10, 9.5); L(15.5, 15); M(11, 19.5); L(20, 19.5); break
      case "undo":
        M(9, 6); L(4, 11); L(9, 16); M(4, 11); L(15, 11); ctx.bezierCurveTo(18.5, 11, 20, 13, 20, 15.5); ctx.bezierCurveTo(20, 18, 18.5, 19.5, 15, 19.5); L(10, 19.5); break
      case "trash":
        M(5, 7); L(19, 7); M(9, 7); L(9, 4.5); L(15, 4.5); L(15, 7); M(7, 7); L(8, 20); L(16, 20); L(17, 7); M(10, 11); L(10, 16); M(14, 11); L(14, 16); break
      case "zoomin":
        C(11, 11, 6.5); M(16, 16); L(21, 21); M(8.5, 11); L(13.5, 11); M(11, 8.5); L(11, 13.5); break
      case "zoomout":
        C(11, 11, 6.5); M(16, 16); L(21, 21); M(8.5, 11); L(13.5, 11); break
      case "search":
        C(11, 11, 6.5); M(16, 16); L(21, 21); break
      case "sticker":
        C(12, 12, 9); M(9, 9.6); L(9, 10.2); M(15, 9.6); L(15, 10.2); M(7.8, 14); ctx.arc(12, 13, 4.9, 0.15 * Math.PI, 0.85 * Math.PI); break
      case "image":
        M(4, 5); L(20, 5); L(20, 19); L(4, 19); ctx.closePath(); C(9, 10, 1.6); M(4, 17); L(9, 12.5); L(13, 16); L(16, 13); L(20, 17); break
      case "film":
        M(4, 6); L(20, 6); L(20, 18); L(4, 18); ctx.closePath(); M(10, 9.5); L(15, 12); L(10, 14.5); ctx.closePath(); break
      case "export":
        M(12, 15); L(12, 4); M(7.5, 8.5); L(12, 4); L(16.5, 8.5); M(5, 14); L(5, 19); L(19, 19); L(19, 14); break
      case "fit":
        M(4, 9); L(4, 4); L(9, 4); M(15, 4); L(20, 4); L(20, 9); M(20, 15); L(20, 20); L(15, 20); M(9, 20); L(4, 20); L(4, 15); break
      case "close":
        M(6, 6); L(18, 18); M(18, 6); L(6, 18); break
      case "rotate":
        M(19, 12); ctx.arc(12, 12, 7, 0, 1.55 * Math.PI, false); M(12, 3.5); L(15.5, 5); L(12, 6.5); break
      case "copy":
        M(9, 9); L(19, 9); L(19, 19); L(9, 19); ctx.closePath(); M(5, 15); L(5, 5); L(15, 5); break
      case "folder":
        M(3.5, 7); L(10, 7); L(12, 9.5); L(20.5, 9.5); L(20.5, 19); L(3.5, 19); ctx.closePath(); break
      case "check":
        M(5, 12.5); L(10, 17.5); L(19, 7); break
      case "front":
        M(8, 8); L(19, 8); L(19, 19); L(8, 19); ctx.closePath(); M(5, 15); L(5, 5); L(15, 5); break
      }
      ctx.stroke()
      ctx.restore()
    }
  }

  component IconButton: Item {
    id: ib
    property string icon: ""
    property bool flip: false
    property string tip: ""
    property string label: ""
    property bool active: false
    property bool primary: false
    property bool danger: false
    property bool tipBelow: false
    signal clicked()
    readonly property color fg: Commons.Color.foreground
    readonly property color ac: Commons.Color.accent
    readonly property bool hovered: ma.containsMouse
    readonly property color content: primary ? ac
      : (danger && hovered ? "#ff6b6b" : (active ? ac : Qt.rgba(fg.r, fg.g, fg.b, hovered ? 1 : 0.78)))
    implicitWidth: label !== "" ? contentRow.implicitWidth + 26 : 34
    implicitHeight: 34
    width: implicitWidth
    height: implicitHeight
    opacity: enabled ? 1 : 0.32
    z: hovered ? 10 : 0

    // The overlay layer blur comes from Hyprland; this low-opacity surface
    // keeps every icon control legible while allowing that blur to show through.
    Rectangle {
      anchors.fill: parent
      radius: 10
      color: ib.active ? Qt.rgba(ib.ac.r, ib.ac.g, ib.ac.b, 0.13)
        : (ib.hovered ? Qt.rgba(ib.fg.r, ib.fg.g, ib.fg.b, 0.10) : root.glassSurface)
      border.width: 1
      border.color: ib.active ? Qt.rgba(ib.ac.r, ib.ac.g, ib.ac.b, 0.32)
        : Qt.rgba(ib.fg.r, ib.fg.g, ib.fg.b, ib.hovered ? 0.18 : 0.065)
      Behavior on color { ColorAnimation { duration: Style.duration(120) } }
      Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
    }

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: ib.icon !== "" && ib.label !== "" ? 7 : 0
      Icon { visible: ib.icon !== ""; anchors.verticalCenter: parent.verticalCenter; name: ib.icon; flip: ib.flip; col: ib.content }
      Text {
        visible: ib.label !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: ib.label
        color: ib.content
        font.pixelSize: 13
        font.weight: Font.Medium
        textFormat: Text.PlainText
      }
    }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: ib.clicked()
    }
    Timer { interval: 450; running: ib.hovered && ib.tip !== ""; onTriggered: root.showTooltip(ib) }
    onHoveredChanged: if (!hovered) root.hideTooltip()
  }

  component Chip: Item {
    id: chip
    property string label: ""
    property bool active: false
    signal clicked()
    readonly property color fg: Commons.Color.foreground
    readonly property color ac: Commons.Color.accent
    implicitWidth: chipText.implicitWidth + 22
    implicitHeight: 28
    width: implicitWidth
    height: implicitHeight
    opacity: enabled ? 1 : 0.38
    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      color: chip.active ? chip.ac : Qt.rgba(chip.fg.r, chip.fg.g, chip.fg.b, chipMa.containsMouse ? 1 : 0.72)
      font.pixelSize: 12
      font.weight: Font.Medium
      textFormat: Text.PlainText
    }
    MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
  }

  component MiniSlider: Controls.Slider {
    id: sl
    implicitHeight: 24
    background: Rectangle {
      x: sl.leftPadding
      y: sl.topPadding + sl.availableHeight / 2 - height / 2
      width: sl.availableWidth
      height: 4
      radius: 2
      color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.16)
      Rectangle { width: sl.visualPosition * parent.width; height: parent.height; radius: 2; color: Commons.Color.accent }
    }
    handle: Rectangle {
      x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
      y: sl.topPadding + sl.availableHeight / 2 - height / 2
      width: 14
      height: 14
      radius: 7
      color: Commons.Color.foreground
      border.width: 0
      scale: sl.hovered ? 1.15 : 1
      Behavior on scale { NumberAnimation { duration: 100 } }
    }
  }

  component MenuRow: Item {
    id: mr
    property string label: ""
    property string hint: ""
    property bool danger: false
    signal clicked()
    readonly property color fg: Commons.Color.foreground
    readonly property bool hovered: mrMa.containsMouse
    width: parent ? parent.width : 180
    height: 32
    Text {
      anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
      text: mr.label; color: mr.danger ? "#ff6b6b" : Qt.rgba(mr.fg.r, mr.fg.g, mr.fg.b, mr.hovered ? 1 : 0.78); font.pixelSize: 13; textFormat: Text.PlainText
    }
    Text {
      anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
      text: mr.hint; color: Qt.rgba(mr.fg.r, mr.fg.g, mr.fg.b, 0.45); font.pixelSize: root.smallFontPx; textFormat: Text.PlainText
    }
    MouseArea { id: mrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mr.clicked() }
  }

  // Drag / wheel / context-menu behaviour shared by emoji and GIF stickers.
  component StickerHandle: MouseArea {
    id: h
    required property var app
    required property string kind
    required property int idx
    property real minSize: 12
    property string pre: ""
    property real sx: 0
    property real sy: 0
    anchors.fill: parent
    enabled: h.app.tool === "select" && !h.app.exporting
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    drag.target: parent
    onPressed: function(mouse) {
      h.app.ctxMenu = null
      h.app.selectedSticker = { kind: h.kind, index: h.idx }
      h.app.card.forceActiveFocus()
      if (mouse.button === Qt.RightButton) {
        var p = h.mapToItem(h.app.card, mouse.x, mouse.y)
        h.app.ctxMenu = { x: p.x, y: p.y }
        return
      }
      h.pre = h.app.snapshot()
      h.sx = h.parent.x
      h.sy = h.parent.y
    }
    onReleased: function(mouse) {
      if (mouse.button === Qt.RightButton) return
      if (h.parent.x !== h.sx || h.parent.y !== h.sy) {
        h.app.pushHistory(h.pre)
        h.app.updateSticker(h.kind, h.idx, { x: h.parent.x, y: h.parent.y })
      }
    }
    onWheel: function(wheel) {
      if (wheel.modifiers & Qt.ControlModifier) { wheel.accepted = false; return }
      var d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
      var it = h.app.getSticker(h.kind, h.idx)
      if (!it) return
      h.app.commitCoalesced()
      var props = { x: h.parent.x, y: h.parent.y }
      if (wheel.modifiers & Qt.AltModifier) {
        props.rotation = ((it.rotation || 0) + (d > 0 ? 5 : -5)) % 360
      } else {
        var ns = Math.max(h.minSize, Math.min(Math.max(200, h.app.imgW), it.size * (d > 0 ? 1.08 : 1 / 1.08)))
        props.size = ns
        props.x = h.parent.x - (ns - it.size) / 2
        props.y = h.parent.y - (ns - it.size) / 2
      }
      h.app.updateSticker(h.kind, h.idx, props)
      wheel.accepted = true
    }
  }
  property alias cardItem: card

  // ───────────────────────── Window ─────────────────────────
  OverlayWindow {
    id: window
    shown: root.opened
    shownKeyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "omarchy-snap-stickers"

    Rectangle {
      anchors.fill: parent
      color: "#1F000000"
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(180) } }
    }

    Item {
      id: card
      readonly property real margin: parent.width < 900 ? 14 : 32
      width: Math.min(parent.width - margin * 2, 1320)
      height: Math.min(parent.height - margin * 2, 880)
      anchors.centerIn: parent
      focus: true
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.97
      Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }

      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        var ctrl = event.modifiers & Qt.ControlModifier
        var shift = event.modifiers & Qt.ShiftModifier
        if (event.key === Qt.Key_Escape) { root.escapePressed(); event.accepted = true; return }
        if (searchInput.activeFocus) return
        if (root.exportDialogOpen && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            && (root.exportState === "idle" || root.exportState === "error")) { root.startExport(); event.accepted = true; return }
        if (ctrl) {
          if (event.key === Qt.Key_Z) { if (shift) root.redo(); else root.undo() }
          else if (event.key === Qt.Key_Y) root.redo()
          else if (event.key === Qt.Key_S) root.exportImage()
          else if (event.key === Qt.Key_D) root.duplicateSelected()
          else if (event.key === Qt.Key_K) { root.exportDialogOpen = false; root.libraryOpen = true; searchInput.forceActiveFocus() }
          else return
          event.accepted = true
          return
        }
        event.accepted = true
        switch (event.key) {
        case Qt.Key_V: root.setTool("select"); break
        case Qt.Key_B: root.setTool("draw"); break
        case Qt.Key_E: root.setTool("erase"); break
        case Qt.Key_BracketLeft: root.brushSize = Math.max(2, root.brushSize - 2); break
        case Qt.Key_BracketRight: root.brushSize = Math.min(48, root.brushSize + 2); break
        case Qt.Key_Delete:
        case Qt.Key_Backspace: root.removeSelectedSticker(); break
        case Qt.Key_R: root.rotateSelected(shift ? -15 : 15); break
        case Qt.Key_Plus:
        case Qt.Key_Equal: root.zoomBy(1.2); break
        case Qt.Key_Minus: root.zoomBy(1 / 1.2); break
        case Qt.Key_0: root.fitView(); break
        default: event.accepted = false
        }
      }

      // ───────── Title bar ─────────
      Item {
        id: titleBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 56

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 18
          anchors.verticalCenter: parent.verticalCenter
          spacing: 11
          Item {
            width: 30; height: 30
            anchors.verticalCenter: parent.verticalCenter
            Icon { anchors.centerIn: parent; name: "sticker"; col: root.accent; width: 22; height: 22 }
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
              text: "Omarchy Snap"
              color: root.fg
              font.pixelSize: Style.font.title
              font.weight: Font.DemiBold
              textFormat: Text.PlainText
            }
            Text {
              visible: !root.compact && root.fileName !== ""
              width: 260
              elide: Text.ElideMiddle
              text: root.fileName
              color: root.alphaOf(root.fg, 0.5)
              font.pixelSize: root.smallFontPx
              textFormat: Text.PlainText
            }
          }
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          IconButton { icon: "image"; tip: "Open screenshot…"; tipBelow: true; onClicked: root.openImageDialog() }
          IconButton {
            icon: "sticker"; tip: "Emoji library  ·  Ctrl+K"; tipBelow: true; active: root.libraryOpen && root.libraryCategory === "Emojis"
            onClicked: root.openEmojiLibrary()
          }
          IconButton {
            primary: true; icon: "export"; tip: "Export  ·  Ctrl+S"; tipBelow: true
            enabled: !root.exporting && !root.processingSticker && sourceImage.status === Image.Ready
            onClicked: root.exportImage()
          }
          IconButton { icon: "close"; danger: true; tip: "Close  ·  Esc"; tipBelow: true; onClicked: root.close() }
        }

      }

      // ───────── Footer ─────────
      Item {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 32
        Text {
          anchors.left: parent.left; anchors.leftMargin: 18; anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 220
          elide: Text.ElideRight
          color: root.alphaOf(root.fg, 0.5)
          font.pixelSize: root.smallFontPx
          textFormat: Text.PlainText
          text: root.processingSticker ? "Converting clip to animated sticker…"
            : (root.drawMode ? "Drag to draw  ·  [ ] brush size  ·  Ctrl+Z undo  ·  Middle-drag to pan"
              : "Drag to move  ·  Scroll to resize  ·  Alt+scroll to rotate  ·  Right-click for options")
        }
        Text {
          anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
          color: root.alphaOf(root.fg, 0.5)
          font.pixelSize: root.smallFontPx
          textFormat: Text.PlainText
          text: root.imgW > 0 ? (Math.round(root.imgW) + " × " + Math.round(root.imgH) + "  ·  " + Math.round(root.viewScale * 100) + "%") : "No image"
        }
      }

      // ───────── Body ─────────
      Item {
        id: body
        anchors.top: titleBar.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12

        // Workspace
        Item {
          id: previewArea
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.right: root.compact ? parent.right : sidebarPanel.left
          anchors.rightMargin: !root.compact && sidebarPanel.width > 0 ? 10 : 0
          clip: true

          Canvas {
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.clearRect(0, 0, width, height)
              ctx.fillStyle = root.alphaOf(root.fg, 0.07)
              for (var x = 14; x < width; x += 22)
                for (var y = 14; y < height; y += 22) ctx.fillRect(x, y, 1.5, 1.5)
            }
          }

          // background: deselect, pan (middle always, left when zoomed), Ctrl+scroll zoom
          MouseArea {
            id: panArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            property real lx: 0
            property real ly: 0
            cursorShape: pressed && (pressedButtons & Qt.MiddleButton) ? Qt.ClosedHandCursor : Qt.ArrowCursor
            onPressed: function(mouse) {
              lx = mouse.x; ly = mouse.y
              root.ctxMenu = null
              card.forceActiveFocus()
              if (mouse.button === Qt.LeftButton) root.selectedSticker = null
            }
            onPositionChanged: function(mouse) {
              if (!pressed) return
              if ((pressedButtons & Qt.MiddleButton) || root.zoom > 1.001) {
                root.panX += mouse.x - lx
                root.panY += mouse.y - ly
              }
              lx = mouse.x; ly = mouse.y
            }
            onWheel: function(wheel) {
              if (wheel.modifiers & Qt.ControlModifier) { root.zoomBy(wheel.angleDelta.y > 0 ? 1.1 : 1 / 1.1); wheel.accepted = true }
              else wheel.accepted = false
            }
          }

          // stage: where the image lives
          Item {
            id: stage
            anchors.fill: parent
            anchors.bottomMargin: toolbarPill.height + ctxStrip.height + 38

            Item {
              id: view
              width: root.imgW
              height: root.imgH
              x: (stage.width - width) / 2 + root.panX
              y: (stage.height - height) / 2 + root.panY
              scale: root.viewScale
              transformOrigin: Item.Center
              visible: root.imgW > 0

              // Everything inside imageCanvas is in source-image pixels and is what gets exported.
              Item {
                id: imageCanvas
                width: root.imgW
                height: root.imgH
                clip: true

                Image {
                  id: sourceImage
                  width: root.imgW
                  height: root.imgH
                  source: root.imagePath ? Util.fileUrl(root.imagePath) : ""
                  asynchronous: true
                  cache: false
                  mipmap: true
                  fillMode: Image.PreserveAspectFit
                }

                Canvas {
                  id: strokeCanvas
                  anchors.fill: parent
                  z: 1
                  property var live: null
                  onWidthChanged: requestPaint()
                  onHeightChanged: requestPaint()
                  onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var all = root.strokes.concat(live ? [live] : [])
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    for (var i = 0; i < all.length; i++) {
                      var st = all[i]
                      ctx.globalCompositeOperation = st.erase ? "destination-out" : "source-over"
                      ctx.strokeStyle = st.erase ? "#000000" : st.color
                      ctx.lineWidth = st.size
                      ctx.beginPath()
                      ctx.moveTo(st.pts[0].x, st.pts[0].y)
                      if (st.pts.length === 1) ctx.lineTo(st.pts[0].x + 0.01, st.pts[0].y)
                      for (var j = 1; j < st.pts.length; j++) ctx.lineTo(st.pts[j].x, st.pts[j].y)
                      ctx.stroke()
                    }
                    ctx.globalCompositeOperation = "source-over"
                  }
                }

                Repeater {
                  model: root.emojiItems
                  delegate: Text {
                    required property var modelData
                    required property int index
                    z: 2
                    x: modelData.x
                    y: modelData.y
                    text: modelData.text
                    font.pixelSize: modelData.size
                    rotation: modelData.rotation || 0
                    textFormat: Text.PlainText
                    Rectangle {
                      anchors.fill: parent
                      color: "transparent"
                      border.color: root.accent
                      border.width: 2 / root.viewScale
                      radius: 6 / root.viewScale
                      visible: !root.exporting && root.selectedSticker !== null && root.selectedSticker.kind === "emoji" && root.selectedSticker.index === index
                    }
                    StickerHandle { app: root; kind: "emoji"; idx: index; minSize: 12 }
                  }
                }

                Repeater {
                  model: root.gifItems
                  delegate: AnimatedImage {
                    required property var modelData
                    required property int index
                    z: 3
                    x: modelData.x
                    y: modelData.y
                    width: modelData.size
                    height: modelData.size
                    rotation: modelData.rotation || 0
                    source: modelData.source
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    playing: root.opened
                    onStatusChanged: {
                      root.recordGifLoad(source, status)
                      if (status === Image.Error) console.warn("Omarchy Snap: could not load animated sticker " + source)
                    }
                    Rectangle {
                      anchors.fill: parent
                      color: "transparent"
                      border.color: root.accent
                      border.width: 2 / root.viewScale
                      radius: 6 / root.viewScale
                      visible: !root.exporting && root.selectedSticker !== null && root.selectedSticker.kind === "gif" && root.selectedSticker.index === index
                    }
                    StickerHandle { app: root; kind: "gif"; idx: index; minSize: 24 }
                  }
                }

                // Drawing surface (only active with brush / eraser)
                MouseArea {
                  id: drawArea
                  anchors.fill: parent
                  z: 5
                  enabled: root.drawMode && !root.exporting
                  visible: enabled
                  acceptedButtons: Qt.LeftButton
                  cursorShape: Qt.CrossCursor
                  onPressed: function(mouse) {
                    root.commit()
                    root.ctxMenu = null
                    card.forceActiveFocus()
                    strokeCanvas.live = {
                      color: String(root.brushColor),
                      size: root.brushSize / root.viewScale,
                      erase: root.tool === "erase",
                      pts: [{ x: mouse.x, y: mouse.y }]
                    }
                    strokeCanvas.requestPaint()
                  }
                  onPositionChanged: function(mouse) {
                    if (!pressed || !strokeCanvas.live) return
                    strokeCanvas.live.pts.push({ x: Math.round(mouse.x * 10) / 10, y: Math.round(mouse.y * 10) / 10 })
                    strokeCanvas.requestPaint()
                  }
                  onReleased: {
                    if (!strokeCanvas.live) return
                    root.strokes = root.strokes.concat([strokeCanvas.live])
                    strokeCanvas.live = null
                    strokeCanvas.requestPaint()
                  }
                }
              }
            }
          }

          // empty state
          Column {
            anchors.centerIn: stage
            spacing: 10
            visible: root.imgW === 0
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "image"; width: 40; height: 40; col: root.alphaOf(root.fg, 0.35) }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: sourceImage.status === Image.Loading ? "Loading screenshot…" : "No screenshot loaded"; color: root.alphaOf(root.fg, 0.55); font.pixelSize: 14; textFormat: Text.PlainText }
          }

          // ── contextual strip ──
      Item {
            id: ctxStrip
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: toolbarPill.top
            anchors.bottomMargin: 8
            height: 46
            width: Math.min(previewArea.width - 36,
              (root.drawMode ? drawRow.implicitWidth : (root.selectedItem ? selRow.implicitWidth : quickRow.implicitWidth)) + 28)
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Rectangle {
              anchors.fill: parent
              radius: 16
              color: root.glassSurface
              border.width: 1
              border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
            }

            // brush / eraser
            Row {
              id: drawRow
              visible: root.drawMode
              anchors.centerIn: parent
              spacing: 10
              Repeater {
                model: root.tool === "draw" ? ["#ff4d4f", "#ffa940", "#ffec3d", "#52c41a", "#40a9ff", "#b37feb", "#ffffff", "#111111"] : []
                delegate: Rectangle {
                  required property string modelData
                  anchors.verticalCenter: parent.verticalCenter
                  width: 22; height: 22; radius: 11
                  color: modelData
                  border.width: 0
                  border.color: "transparent"
                  scale: String(root.brushColor) === String(Qt.color(modelData)) || swMa.containsMouse ? 1.12 : 1
                  Behavior on scale { NumberAnimation { duration: 100 } }
                  MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.brushColor = modelData }
                }
              }
              Text { visible: root.tool === "erase"; anchors.verticalCenter: parent.verticalCenter; text: "Eraser"; color: root.alphaOf(root.fg, 0.8); font.pixelSize: root.mediumFontPx; textFormat: Text.PlainText }
              MiniSlider { id: brushSlider; anchors.verticalCenter: parent.verticalCenter; width: 120; from: 2; to: 48; stepSize: 1; onMoved: root.brushSize = Math.round(value) }
              Binding { target: brushSlider; property: "value"; value: root.brushSize; restoreMode: Binding.RestoreNone }
              Text { anchors.verticalCenter: parent.verticalCenter; width: 32; text: root.brushSize + " px"; color: root.alphaOf(root.fg, 0.65); font.pixelSize: 12; textFormat: Text.PlainText }
            }

            // selected sticker
            Row {
              id: selRow
              visible: !root.drawMode && root.selectedItem !== null
              anchors.centerIn: parent
              spacing: 6
              Text { anchors.verticalCenter: parent.verticalCenter; text: root.selectedSticker && root.selectedSticker.kind === "gif" ? "GIF" : "Emoji"; color: root.alphaOf(root.fg, 0.65); font.pixelSize: 12; font.weight: Font.Medium; textFormat: Text.PlainText }
              MiniSlider {
                id: sizeSlider
                anchors.verticalCenter: parent.verticalCenter
                width: 110
                from: 16
                to: Math.max(240, root.imgW * 0.6)
                onPressedChanged: if (pressed) root.commit()
                onMoved: if (root.selectedSticker) root.updateSticker(root.selectedSticker.kind, root.selectedSticker.index, { size: value })
              }
              Binding { target: sizeSlider; property: "value"; value: root.selectedItem ? root.selectedItem.size : 16; restoreMode: Binding.RestoreNone }
              IconButton { icon: "rotate"; flip: true; tip: "Rotate left  ·  Shift+R"; onClicked: root.rotateSelected(-15) }
              IconButton { icon: "rotate"; tip: "Rotate right  ·  R"; onClicked: root.rotateSelected(15) }
              IconButton { icon: "copy"; tip: "Duplicate  ·  Ctrl+D"; onClicked: root.duplicateSelected() }
              IconButton { icon: "trash"; danger: true; tip: "Remove  ·  Del"; onClicked: root.removeSelectedSticker() }
            }

            // quick stickers
            Row {
              id: quickRow
              visible: !root.drawMode && root.selectedItem === null
              anchors.centerIn: parent
              spacing: 4
              Repeater {
                model: root.quickEmoji
                delegate: Item {
                  required property string modelData
                  width: 32; height: 32
                  Text { anchors.centerIn: parent; text: modelData; font.pixelSize: 19; textFormat: Text.PlainText; scale: qMa.containsMouse ? 1.15 : 1; Behavior on scale { NumberAnimation { duration: 100 } } }
                  MouseArea { id: qMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.addEmoji(modelData) }
                }
              }
              Repeater {
                model: root.bundledGifs
                delegate: Item {
                  required property var modelData
                  width: 32; height: 32
                  Text { anchors.centerIn: parent; text: modelData.label; font.pixelSize: 19; textFormat: Text.PlainText }
                  Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 2; width: 5; height: 5; radius: 3; color: root.accent }
                  MouseArea { id: gMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.addGif(modelData.source, false) }
                }
              }
            }
          }

          // ── floating toolbar ──
          Item {
            id: toolbarPill
            readonly property real natural: {
              var s = 0
              for (var i = 0; i < tbFlow.children.length; i++) s += tbFlow.children[i].width + tbFlow.spacing
              return s - tbFlow.spacing
            }
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            width: Math.min(natural, previewArea.width - 56) + 20
            height: tbFlow.height + 16

            Rectangle {
              anchors.fill: parent
              radius: 18
              color: root.glassSurface
              border.width: 1
              border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
              Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; radius: 1; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12) }
            }

            Flow {
              id: tbFlow
              x: 10
              y: 8
              width: toolbarPill.width - 20
              spacing: 7

              IconButton { icon: "select"; tip: "Select & move  ·  V"; active: root.tool === "select"; onClicked: root.setTool("select") }
              IconButton { icon: "brush"; tip: "Brush  ·  B"; active: root.tool === "draw"; onClicked: root.setTool("draw") }
              IconButton { icon: "eraser"; tip: "Eraser (brush strokes)  ·  E"; active: root.tool === "erase"; onClicked: root.setTool("erase") }
              IconButton { icon: "undo"; tip: "Undo  ·  Ctrl+Z"; enabled: root.undoStack.length > 0; onClicked: root.undo() }
              IconButton { icon: "undo"; flip: true; tip: "Redo  ·  Ctrl+Shift+Z"; enabled: root.redoStack.length > 0; onClicked: root.redo() }
              IconButton { icon: "trash"; danger: true; tip: "Clear canvas"; enabled: root.hasContent; onClicked: root.clearCanvas() }
              IconButton { icon: "sticker"; tip: "Emoji library  ·  Ctrl+K"; active: root.libraryOpen && root.libraryCategory === "Emojis"; onClicked: root.openEmojiLibrary() }
              IconButton { icon: "film"; tip: "GIF library"; active: root.libraryOpen && root.libraryCategory === "Animated"; enabled: !root.processingSticker; onClicked: root.openGifLibrary() }
              IconButton { icon: "zoomout"; tip: "Zoom out  ·  −"; onClicked: root.zoomBy(1 / 1.2) }
              IconButton { icon: "zoomin"; tip: "Zoom in  ·  +"; onClicked: root.zoomBy(1.2) }
              IconButton {
                icon: "fit"
                active: root.viewIsFitted
                tip: root.viewIsFitted ? "Image fitted to window  ·  0" : "Fit to window  ·  0"
                onClicked: root.fitView()
              }
            }
          }

          // conversion / busy chip
          Item {
            visible: root.processingSticker
            anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; anchors.topMargin: 14
            height: 30; width: busyText.implicitWidth + 28
            Text { id: busyText; anchors.centerIn: parent; text: "Converting clip…"; color: root.accent; font.pixelSize: root.mediumFontPx; textFormat: Text.PlainText }
          }
        }

        // Shared right sidebar: one shell, with library and export content modes.
        Item {
          id: sidebarPanel
          anchors.right: parent.right
          anchors.top: parent.top
          height: root.sidebarMode === "export" ? Math.min(parent.height, dlgCol.implicitHeight + 28) : parent.height
          width: root.sidebarMode !== "closed" ? Math.min(330, body.width - (root.compact ? 0 : 160)) : 0
          visible: width > 1
          clip: true
          z: 5
          Behavior on width { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
          Behavior on height { NumberAnimation { duration: Style.duration(200); easing.type: Easing.OutCubic } }

          Rectangle {
            anchors.fill: parent
            color: root.glassSurface
            border.width: 1
            border.color: root.alphaOf(root.fg, 0.13)
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; radius: 1; color: root.alphaOf(root.fg, 0.16) }
          }

          Item {
            id: libraryContent
            width: parent.width
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: root.sidebarMode === "library"
            clip: true

            Item {
              id: libHeader
              anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
              anchors.margins: 14
              height: 34
              Text { anchors.verticalCenter: parent.verticalCenter; text: root.libraryCategory === "Animated" ? "GIF library" : (root.libraryCategory === "Emojis" ? "Emoji library" : "Stickers"); color: root.fg; font.pixelSize: 15; font.weight: Font.DemiBold; textFormat: Text.PlainText }
              IconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; icon: "close"; tip: "Close library"; onClicked: root.libraryOpen = false }
            }

            Item {
              id: searchBox
              // A lightly tinted, translucent surface lets the compositor's
              // layer blur show through while keeping the search field legible.
              Rectangle {
                anchors.fill: parent
                radius: 11
                color: searchInput.activeFocus ? root.alphaOf(root.accent, 0.10) : root.glassSurface
                border.width: 1
                border.color: searchInput.activeFocus ? root.alphaOf(root.accent, 0.38) : root.alphaOf(root.fg, 0.12)
                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on border.color { ColorAnimation { duration: 140 } }
              }
              anchors.top: libHeader.bottom; anchors.topMargin: 4
              anchors.left: parent.left; anchors.right: parent.right
              anchors.leftMargin: 14; anchors.rightMargin: 14
              height: 38
              Icon { id: searchIcon; anchors.left: parent.left; anchors.leftMargin: 11; anchors.verticalCenter: parent.verticalCenter; name: "search"; col: root.alphaOf(root.fg, 0.55) }
              TextInput {
                id: searchInput
                anchors.left: searchIcon.right; anchors.leftMargin: 9
                anchors.right: clearBtn.left; anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                color: root.fg
                font.pixelSize: 13
                clip: true
                selectByMouse: true
                selectionColor: root.alphaOf(root.accent, 0.5)
                onTextChanged: root.libraryQuery = text
                Text { visible: !parent.text && !parent.activeFocus; text: root.libraryCategory === "Animated" ? "Search GIFs" : (root.libraryCategory === "Emojis" ? "Search emojis" : "Search stickers"); color: root.alphaOf(root.fg, 0.4); font.pixelSize: 13; textFormat: Text.PlainText }
              }
              Item {
                id: clearBtn
                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22
                visible: searchInput.text !== ""
                Icon { anchors.centerIn: parent; width: 14; height: 14; name: "close"; col: root.alphaOf(root.fg, 0.6) }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { searchInput.text = ""; card.forceActiveFocus() } }
              }
            }

            Flow {
              id: catFlow
              anchors.top: searchBox.bottom; anchors.topMargin: 10
              anchors.left: parent.left; anchors.right: parent.right
              anchors.leftMargin: 14; anchors.rightMargin: 14
              spacing: 6
              Repeater {
                model: root.libraryCategories
                delegate: Chip {
                  required property string modelData
                  label: modelData
                  active: root.libraryCategory === modelData
                  onClicked: { root.libraryCategory = modelData; card.forceActiveFocus() }
                }
              }
            }

            GridView {
              id: libGrid
              anchors.top: catFlow.bottom; anchors.topMargin: 12
              anchors.bottom: libFooter.top; anchors.bottomMargin: 6
              anchors.left: parent.left; anchors.right: parent.right
              anchors.leftMargin: 11; anchors.rightMargin: 11
              clip: true
              cellWidth: Math.floor(width / 5)
              cellHeight: cellWidth
              model: root.libraryModel
              boundsBehavior: Flickable.StopAtBounds
              Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
              delegate: Item {
                id: cell
                required property var modelData
                width: libGrid.cellWidth
                height: libGrid.cellHeight
                readonly property bool active: root.isActiveCell(modelData)
                Item {
                  anchors.fill: parent
                  anchors.margins: 3
                  scale: cell.active ? 1.08 : (cellMa.pressed ? 0.94 : 1)
                  Behavior on scale { NumberAnimation { duration: 90 } }
                  Text {
                    visible: cell.modelData.kind === "emoji"
                    anchors.centerIn: parent
                    text: cell.modelData.kind === "emoji" ? cell.modelData.text : ""
                    font.pixelSize: 26
                    textFormat: Text.PlainText
                  }
                  AnimatedImage {
                    visible: cell.modelData.kind === "gif"
                    anchors.fill: parent
                    anchors.margins: 8
                    source: cell.modelData.kind === "gif" ? cell.modelData.source : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    playing: root.opened && root.libraryOpen
                    onStatusChanged: {
                      root.recordGifLoad(source, status)
                      if (status === Image.Error) console.warn("Omarchy Snap: could not load animated sticker " + source)
                    }
                  }
                  Text {
                    id: gifTag
                    visible: cell.modelData.kind === "gif"
                    anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 4
                    text: "GIF"
                    color: root.accent
                    font.pixelSize: root.tinyFontPx
                    font.weight: Font.Bold
                    textFormat: Text.PlainText
                  }
                  MouseArea {
                    id: cellMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: root.libraryHover = containsMouse ? cell.modelData.name : ""
                    onClicked: {
                      if (cell.modelData.kind === "emoji") root.addEmoji(cell.modelData.text)
                      else root.addGif(cell.modelData.source, false)
                      card.forceActiveFocus()
                    }
                  }
                }
              }
            }

            Text {
              anchors.centerIn: libGrid
              visible: root.libraryModel.length === 0
              text: "No stickers match “" + root.libraryQuery + "”"
              color: root.alphaOf(root.fg, 0.5)
              font.pixelSize: root.mediumFontPx
              textFormat: Text.PlainText
            }

            Item {
              id: libFooter
              anchors.bottom: parent.bottom
              anchors.left: parent.left; anchors.right: parent.right
              anchors.margins: 14
              height: 44
              Text {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 140
                elide: Text.ElideRight
                text: root.libraryHover !== "" ? root.libraryHover : (root.libraryModel.length + " stickers")
                color: root.alphaOf(root.fg, 0.55)
                font.pixelSize: 12
                textFormat: Text.PlainText
              }
              IconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; icon: "film"; tip: "Add a GIF, WebP or MP4 clip"; enabled: !root.processingSticker; onClicked: root.addCustomGif() }
            }
          }
          Item {
            id: exportContent
            anchors.fill: parent
            visible: root.sidebarMode === "export"
            clip: true
            Column {
              id: dlgCol
              anchors.fill: parent; anchors.margins: 14; spacing: 14

              Item {
                width: parent.width; height: 34
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Export"; color: root.fg; font.pixelSize: 15; font.weight: Font.DemiBold; textFormat: Text.PlainText }
                IconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; icon: "close"; tip: "Close export panel"; enabled: !root.exporting; onClicked: root.exportDialogOpen = false }
              }

              Column { width: parent.width; spacing: 8
                Text { text: "FORMAT"; color: root.alphaOf(root.fg, 0.55); font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.1; textFormat: Text.PlainText }
                Flow { width: parent.width; spacing: 6
                  Chip { label: "PNG"; active: root.exportFormat === "png"; enabled: !root.exporting; onClicked: root.exportFormat = "png" }
                  Chip { label: "GIF"; active: root.exportFormat === "gif"; enabled: !root.exporting && root.hasAnimatedStickers; onClicked: root.exportFormat = "gif" }
                  Chip { label: "MP4"; active: root.exportFormat === "mp4"; enabled: !root.exporting && root.hasAnimatedStickers; onClicked: root.exportFormat = "mp4" }
                }
              }

              Text {
                width: parent.width; wrapMode: Text.WordWrap
                color: root.alphaOf(root.fg, 0.72); font.pixelSize: 12; textFormat: Text.PlainText
                text: (root.exportFormat === "png" ? "Still image at full resolution. Saved and copied to the clipboard."
                  : root.exportFormat === "gif" ? "Animated GIF, up to 1280 px. Saved and copied to the clipboard."
                  : "H.264 video, up to 1280 px. Saved to disk and the file path is copied.")
                  + (root.hasAnimatedStickers ? "" : " Add an animated sticker to unlock GIF and MP4.")
              }

              Column { width: parent.width; spacing: 8
                Row { width: parent.width
                  Text { text: "QUALITY"; color: root.alphaOf(root.fg, 0.55); font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.1; textFormat: Text.PlainText }
                  Text { anchors.right: parent.right; text: root.exportFormat === "png" ? "Lossless" : (Math.round(root.exportQuality) + "%"); color: root.exportFormat === "png" ? root.alphaOf(root.fg, 0.55) : root.accent; font.pixelSize: 11; textFormat: Text.PlainText }
                }
                MiniSlider { width: parent.width; from: 50; to: 100; value: root.exportQuality; enabled: !root.exporting && root.exportFormat !== "png"; onMoved: root.exportQuality = value; onValueChanged: if (!pressed) root.exportQuality = value }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: root.exportFormat === "png" ? "PNG keeps full resolution with lossless quality." : "Higher quality preserves more detail and creates larger files."; color: root.alphaOf(root.fg, 0.55); font.pixelSize: 11; textFormat: Text.PlainText }
              }

              Column { width: parent.width; spacing: 6
                Text { text: "SAVE LOCATION"; color: root.alphaOf(root.fg, 0.55); font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.1; textFormat: Text.PlainText }
                Item { width: parent.width; height: 34
                  Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: root.glassSurface
                    border.width: 1
                    border.color: root.alphaOf(root.fg, 0.12)
                  }
                  Text {
                    anchors.fill: parent; anchors.leftMargin: 11; anchors.rightMargin: 11
                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideMiddle
                    text: root.exportState === "done" && root.lastOutputPath !== "" ? root.lastOutputPath : root.outputDir
                    color: root.fg; font.pixelSize: 12; font.family: "monospace"; textFormat: Text.PlainText
                  }
                }
              }

              Column { width: parent.width; spacing: 8; visible: root.exportState !== "idle"
                Item { width: parent.width; height: 3
                  Rectangle {
                    height: parent.height; radius: 2; width: parent.width * root.exportProgress
                    color: root.exportState === "error" ? "#ff6b6b" : (root.exportState === "done" ? "#5bd68a" : root.accent)
                    Behavior on width { NumberAnimation { duration: 120 } }
                  }
                }
                Row { width: parent.width; spacing: 8
                  Icon { visible: root.exportState === "done"; anchors.verticalCenter: parent.verticalCenter; name: "check"; col: "#5bd68a" }
                  Icon { visible: root.exportState === "error"; anchors.verticalCenter: parent.verticalCenter; name: "close"; col: "#ff6b6b" }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter; width: dlgCol.width - 26
                    wrapMode: Text.WordWrap; text: root.exportMessage
                    color: root.exportState === "error" ? "#ff6b6b" : (root.exportState === "done" ? "#5bd68a" : root.alphaOf(root.fg, 0.75))
                    font.pixelSize: root.mediumFontPx; textFormat: Text.PlainText
                  }
                }
              }

              Item {
                width: parent.width; height: actionFlow.implicitHeight
                Flow { id: actionFlow; anchors.left: parent.left; anchors.right: parent.right; spacing: 6
                  IconButton {
                    visible: root.exportState === "idle" || root.exportState === "error"
                    width: 76
                    tip: root.exportState === "error" ? "Close export options" : "Cancel export"
                    label: root.exportState === "error" ? "Close" : "Cancel"
                    onClicked: root.exportDialogOpen = false
                  }
                  IconButton {
                    visible: root.exportState === "idle" || root.exportState === "error"
                    width: parent.width - 82; primary: true; icon: "export"
                    tip: root.exportState === "error" ? "Retry export" : "Export image"
                    label: root.exportState === "error" ? "Retry export" : "Export"
                    onClicked: root.startExport()
                  }
                  IconButton { visible: root.exportState === "working"; enabled: false; tip: root.exportMessage; label: "Exporting…" }
                  IconButton { visible: root.exportState === "done"; enabled: !copyExportProc.running; icon: "copy"; tip: "Copy exported file"; label: copyExportProc.running ? "Copying…" : "Copy file"; onClicked: root.copyExport() }
                  IconButton { visible: root.exportState === "done"; icon: "copy"; tip: "Copy file path"; label: "Copy path"; onClicked: copyPathProc.running = true }
                  IconButton { visible: root.exportState === "done"; icon: "folder"; tip: "Open save folder"; label: "Open folder"; onClicked: openFolderProc.running = true }
                  IconButton { visible: root.exportState === "done"; primary: true; tip: "Close Omarchy Snap"; label: "Done"; onClicked: root.close() }
                }
              }
            }
          }
        }
      }

      // ───────── Context menu ─────────
      MouseArea {
        anchors.fill: parent
        z: 40
        visible: root.ctxMenu !== null
        acceptedButtons: Qt.AllButtons
        onPressed: root.ctxMenu = null
      }
      Item {
        id: ctxMenuBox
        z: 41
        visible: root.ctxMenu !== null
        opacity: visible ? 1 : 0
        width: 210
        height: menuCol.implicitHeight + 12
        x: root.ctxMenu ? Math.min(root.ctxMenu.x, card.width - width - 10) : 0
        y: root.ctxMenu ? Math.min(root.ctxMenu.y, card.height - height - 10) : 0
        Column {
          id: menuCol
          anchors.fill: parent
          anchors.margins: 6
          spacing: 2
          MenuRow { label: "Duplicate"; hint: "Ctrl+D"; onClicked: { root.ctxMenu = null; root.duplicateSelected() } }
          MenuRow { label: "Bring to front"; onClicked: { root.ctxMenu = null; root.bringToFront() } }
          MenuRow { label: "Rotate right"; hint: "R"; onClicked: { root.ctxMenu = null; root.rotateSelected(15) } }
          MenuRow {
            label: "Reset rotation"
            onClicked: { root.ctxMenu = null; if (root.selectedSticker) { root.commit(); root.updateSticker(root.selectedSticker.kind, root.selectedSticker.index, { rotation: 0 }) } }
          }
          MenuRow { label: "Remove"; hint: "Del"; danger: true; onClicked: { root.ctxMenu = null; root.removeSelectedSticker() } }
        }
      }
    }

    Item {
      id: tooltipLayer
      anchors.fill: parent
      z: 1000
      enabled: false

      Item {
        id: tooltipBubble
        width: tooltipLabel.implicitWidth + 18
        height: tooltipLabel.implicitHeight + 12
        x: Math.max(8, Math.min(parent.width - width - 8, root.tooltipX - width / 2))
        y: Math.max(8, Math.min(parent.height - height - 8, root.tooltipBelow ? root.tooltipY : root.tooltipY - height))
        opacity: root.tooltipText !== "" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Style.duration(130); easing.type: Easing.OutCubic } }
        z: 1001

        Rectangle {
          anchors.fill: parent
          radius: 8
          color: root.glassSurface
          border.width: 1
          border.color: root.alphaOf(root.fg, 0.16)
        }
        Text {
          id: tooltipLabel
          anchors.centerIn: parent
          text: root.tooltipText
          color: root.fg
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }
      }
    }
  }
}
