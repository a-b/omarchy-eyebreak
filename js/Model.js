// Pure timer logic for Eye Break. No Qt imports, so node can test it.
// Times are epoch milliseconds; durations are milliseconds.

var DEFAULTS = {
  blinkEnabled: true,
  farEnabled: true,
  blinkEveryMinutes: 10,
  blinkSeconds: 3,
  farEveryMinutes: 20,
  farSeconds: 20,
  opacityPercent: 50,
  dismissOnClick: false,
  showBorder: true
}

// A tick gap longer than this means the machine slept: treat it as a break.
var MAX_STEP_MS = 60000
// How long a look-far break held by Do Not Disturb waits before asking again.
var RECHECK_MS = 60000
// "Pause until tomorrow" ends at this local hour.
var WAKE_HOUR = 6

function bool(value, fallback) {
  if (value === true || value === "true") return true
  if (value === false || value === "false") return false
  return fallback
}

function int(value, fallback, min, max) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return fallback
  return Math.min(max, Math.max(min, n))
}

// Widget settings from shell.json, with every value bounded.
function config(settings) {
  var s = settings || {}
  return {
    blinkEnabled: bool(s.blinkEnabled, DEFAULTS.blinkEnabled),
    farEnabled: bool(s.farEnabled, DEFAULTS.farEnabled),
    blinkEveryMs: int(s.blinkEveryMinutes, DEFAULTS.blinkEveryMinutes, 1, 60) * 60000,
    blinkShowMs: int(s.blinkSeconds, DEFAULTS.blinkSeconds, 1, 10) * 1000,
    farEveryMs: int(s.farEveryMinutes, DEFAULTS.farEveryMinutes, 1, 120) * 60000,
    farShowMs: int(s.farSeconds, DEFAULTS.farSeconds, 5, 120) * 1000,
    opacity: int(s.opacityPercent, DEFAULTS.opacityPercent, 20, 100) / 100,
    dismissOnClick: bool(s.dismissOnClick, DEFAULTS.dismissOnClick),
    showBorder: bool(s.showBorder, DEFAULTS.showBorder)
  }
}

// Reminder offset from centre, as a fraction of the free space on one side:
// two uniform draws summed peak at 0, so cards land near the middle more often.
var SPREAD = 0.5
function nearCenter(r1, r2) {
  return (r1 + r2 - 1) * SPREAD
}

function initial() {
  return { farMs: 0, blinkMs: 0, pausedUntil: 0, recheckAt: 0 }
}

function with_(s, changes) {
  var out = {}
  for (var k in s) out[k] = s[k]
  for (var c in changes) out[c] = changes[c]
  return out
}

function isPaused(s, now) {
  return s.pausedUntil > now
}

// Both clocks restart: the eyes have just rested.
function rested(s) {
  return with_(s, { farMs: 0, blinkMs: 0, recheckAt: 0 })
}

// Adds active screen time since the last tick.
function advance(s, dtMs, now) {
  if (isPaused(s, now) || !(dtMs > 0)) return s
  if (dtMs > MAX_STEP_MS) return rested(s)
  return with_(s, { farMs: s.farMs + dtMs, blinkMs: s.blinkMs + dtMs })
}

// The reminder that is due now: "far" wins over "blink", "" for none.
function due(s, now, cfg) {
  if (isPaused(s, now)) return ""
  if (cfg.farEnabled && s.farMs >= cfg.farEveryMs && now >= s.recheckAt) return "far"
  if (cfg.blinkEnabled && s.blinkMs >= cfg.blinkEveryMs) return "blink"
  return ""
}

function shown(s, kind) {
  return kind === "far" ? rested(s) : with_(s, { blinkMs: 0 })
}

// A hold (DND, screen share) drops a blink nudge but keeps a look-far break due.
function held(s, kind, now) {
  return kind === "far" ? with_(s, { recheckAt: now + RECHECK_MS }) : with_(s, { blinkMs: 0 })
}

// When a hold that has a change signal (screen share) ends, ask at once.
function holdLifted(s) {
  return with_(s, { recheckAt: 0 })
}

function pauseUntil(now, choice) {
  if (choice === "tomorrow") {
    var d = new Date(now)
    d.setHours(WAKE_HOUR, 0, 0, 0)
    if (d.getTime() <= now) d.setDate(d.getDate() + 1)
    return d.getTime()
  }
  var minutes = Number(choice)
  if (!isFinite(minutes) || minutes <= 0) return 0
  return now + Math.min(minutes, 24 * 60) * 60000
}

function pause(s, now, choice) {
  var until = pauseUntil(now, choice)
  return until > now ? with_(s, { pausedUntil: until }) : s
}

// Coming back from a pause starts a fresh cycle.
function resume(s) {
  return rested(with_(s, { pausedUntil: 0 }))
}

function farRemainingMs(s, cfg) {
  return Math.max(0, cfg.farEveryMs - s.farMs)
}

function blinkRemainingMs(s, cfg) {
  return Math.max(0, cfg.blinkEveryMs - s.blinkMs)
}

// "45 s", "12 min", "1 h 5 min".
function fmt(ms) {
  var sec = Math.max(0, Math.round(ms / 1000))
  if (sec < 60) return sec + " s"
  var min = Math.round(sec / 60)
  if (min < 60) return min + " min"
  var h = Math.floor(min / 60), m = min % 60
  return h + " h" + (m ? " " + m + " min" : "")
}

function clock(ms) {
  var d = new Date(ms)
  return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0")
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULTS: DEFAULTS, MAX_STEP_MS: MAX_STEP_MS, RECHECK_MS: RECHECK_MS,
    config: config, initial: initial, isPaused: isPaused, rested: rested,
    advance: advance, due: due, shown: shown, held: held, holdLifted: holdLifted,
    pauseUntil: pauseUntil, pause: pause, resume: resume,
    farRemainingMs: farRemainingMs, blinkRemainingMs: blinkRemainingMs,
    fmt: fmt, clock: clock, nearCenter: nearCenter
  }
}
