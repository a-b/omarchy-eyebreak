import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs.Commons
import "../js/Model.js" as Model

// Counts active screen time and shows the blink and look-far reminders on
// every screen. Headless apart from those windows; the bar widget reads the
// state from here and pushes its shell.json settings in.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  property var settings: ({})
  readonly property var cfg: Model.config(settings)
  property var state: Model.initial()
  property double now: Date.now()
  property double lastTick: Date.now()
  property string showing: ""   // "", "blink" or "far"
  property string last: ""      // latest reminder outcome, for `status`
  property string checking: ""  // the reminder waiting on the DND answer

  readonly property bool paused: Model.isPaused(state, now)
  readonly property double farRemainingMs: Model.farRemainingMs(state, cfg)
  readonly property double blinkRemainingMs: Model.blinkRemainingMs(state, cfg)

  function applySettings(values) { settings = values || {} }

  // ---- Idle: 20 s without input is a rest. Inhibitors (video, calls) keep
  // the user counted as present, so watching still needs breaks.
  readonly property bool userIdle: idleMonitor.isIdle
  IdleMonitor {
    id: idleMonitor
    timeout: 20
    respectInhibitors: true
  }
  onUserIdleChanged: {
    if (userIdle) state = Model.rested(state)
    lastTick = Date.now()
  }

  // ---- Screen sharing: the portal's PipeWire stream, as the notification
  // service detects it. Third-party plugins cannot read that service.
  readonly property var videoSources: {
    var nodes = Pipewire.nodes.values, out = []
    for (var i = 0; i < nodes.length && out.length < 64; i++)
      if (nodes[i].type === PwNodeType.VideoSource) out.push(nodes[i])
    return out
  }
  PwObjectTracker { objects: root.videoSources }
  readonly property bool sharing: {
    if (!Pipewire.ready) return false
    for (var i = 0; i < videoSources.length; i++) {
      var node = videoSources[i]
      if (!node.ready) continue
      var props = node.properties
      if (props["media.class"] === "Video/Source"
          && String(props["media.name"] || "").indexOf("xdph-streaming-") === 0) return true
    }
    return false
  }
  onSharingChanged: if (!sharing) state = Model.holdLifted(state)

  // ---- Clock. No process runs per tick; DND is asked only when a reminder is due.
  Timer {
    interval: 5000
    repeat: true
    running: !root.userIdle
    onTriggered: root.tick()
  }

  function tick() {
    var t = Date.now()
    now = t
    state = Model.advance(state, t - lastTick, t)
    lastTick = t
    if (showing !== "" || checking !== "") return
    var kind = Model.due(state, t, cfg)
    if (!kind) return
    if (sharing) hold(kind, t, "sharing")
    else {
      checking = kind
      dndProc.running = true
      dndWatchdog.restart()
    }
  }

  // Ends a DND check. A command that fails to start, hangs or never closes its
  // output would otherwise leave `checking` set and stop every later reminder.
  function finishCheck(dndOn) {
    dndWatchdog.stop()
    var kind = checking
    if (!kind) return
    checking = ""
    var t = Date.now()
    // Paused, rested or switched off while asking.
    if (Model.due(state, t, cfg) !== kind) return
    if (dndOn) hold(kind, t, "dnd")
    else show(kind)
  }

  function hold(kind, t, why) {
    state = Model.held(state, kind, t)
    last = kind + " held (" + why + ") " + Model.clock(t)
  }

  Process {
    id: dndProc
    // No -q: it silences the answer too, which reads as DND off.
    command: ["omarchy-shell", "notifications", "dndState"]
    stdout: StdioCollector {
      onStreamFinished: root.finishCheck(text.trim() === "on")
    }
  }

  // No answer in time counts as DND off: a missed hold beats a silent plugin.
  Timer {
    id: dndWatchdog
    interval: 3000
    onTriggered: {
      dndProc.running = false
      root.finishCheck(false)
    }
  }

  function show(kind) {
    state = Model.shown(state, kind)
    last = kind + " shown " + Model.clock(Date.now())
    showing = kind
    hideTimer.interval = kind === "far" ? cfg.farShowMs : cfg.blinkShowMs
    hideTimer.restart()
  }

  function dismiss() {
    hideTimer.stop()
    showing = ""
  }

  Timer {
    id: hideTimer
    onTriggered: root.showing = ""
  }

  function pause(choice) {
    state = Model.pause(state, Date.now(), choice)
    now = Date.now()
    if (paused) dismiss()
  }

  function resume() {
    state = Model.resume(state)
    now = Date.now()
  }

  Variants {
    model: Quickshell.screens
    Reminder {
      required property var modelData
      screen: modelData
      service: root
    }
  }

  ShellIpc {
    target: "a-b.eyebreak"

    function status(): string {
      return JSON.stringify({
        showing: root.showing, last: root.last, paused: root.paused, pausedUntil: root.state.pausedUntil,
        idle: root.userIdle, sharing: root.sharing,
        farInSeconds: Math.round(root.farRemainingMs / 1000),
        blinkInSeconds: Math.round(root.blinkRemainingMs / 1000),
        farEnabled: root.cfg.farEnabled, blinkEnabled: root.cfg.blinkEnabled
      })
    }
    function pause(choice: string): string {
      root.pause(choice)
      return root.paused ? "paused until " + Model.clock(root.state.pausedUntil) : "invalid: minutes or tomorrow"
    }
    function resume(): string { root.resume(); return "ok" }
    function breakNow(): string { root.show("far"); return "ok" }
    function blinkNow(): string { root.show("blink"); return "ok" }
    function dismiss(): string { root.dismiss(); return "ok" }
  }
}
