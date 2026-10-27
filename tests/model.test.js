"use strict"

const { test } = require("node:test")
const assert = require("node:assert/strict")
const M = require("../js/Model.js")

const cfg = M.config({})
const MIN = 60000
const T0 = new Date(2026, 9, 26, 10, 0).getTime()

function run(s, minutes, now) {
  for (let i = 0; i < minutes * 12; i++) s = M.advance(s, 5000, now)
  return s
}

test("defaults follow 20-20-20 with a 10 min blink nudge", () => {
  assert.equal(cfg.farEveryMs, 20 * MIN)
  assert.equal(cfg.farShowMs, 20000)
  assert.equal(cfg.blinkEveryMs, 10 * MIN)
})

test("blink is due at 10 min, look-far at 20 min and wins", () => {
  let s = run(M.initial(), 9.9, T0)
  assert.equal(M.due(s, T0, cfg), "")
  s = run(s, 0.1, T0)
  assert.equal(M.due(s, T0, cfg), "blink")
  s = M.shown(s, "blink")
  s = run(s, 10, T0)
  assert.equal(M.due(s, T0, cfg), "far")
  s = M.shown(s, "far")
  assert.equal(s.farMs, 0)
  assert.equal(s.blinkMs, 0)
})

test("disabled reminders never come due", () => {
  const off = M.config({ blinkEnabled: false, farEnabled: "false" })
  assert.equal(M.due(run(M.initial(), 30, T0), T0, off), "")
})

test("a long tick gap (suspend) counts as a rest", () => {
  let s = run(M.initial(), 15, T0)
  s = M.advance(s, M.MAX_STEP_MS + 1, T0)
  assert.equal(s.farMs, 0)
})

test("hold drops blink but keeps look-far due, re-asked after a minute", () => {
  let s = run(M.initial(), 20, T0)
  s = M.held(s, "far", T0)
  assert.equal(M.due(s, T0 + 1000, cfg), "blink") // look-far waits; blink still eligible
  s = M.held(s, "blink", T0 + 1000)
  assert.equal(s.blinkMs, 0)
  assert.equal(M.due(s, T0 + 2000, cfg), "")
  assert.equal(M.due(s, T0 + M.RECHECK_MS, cfg), "far")
  assert.equal(M.due(M.holdLifted(s), T0 + 2000, cfg), "far")
})

test("pause stops counting and expires; resume starts fresh", () => {
  let s = M.pause(run(M.initial(), 19, T0), T0, 15)
  assert.equal(M.isPaused(s, T0), true)
  s = run(s, 5, T0)
  assert.equal(s.farMs, 19 * MIN)
  assert.equal(M.due(run(s, 1, T0), T0, cfg), "")
  assert.equal(M.isPaused(s, T0 + 15 * MIN), false)
  s = M.resume(s)
  assert.equal(s.pausedUntil, 0)
  assert.equal(s.farMs, 0)
})

test("pause until tomorrow ends at the next 06:00", () => {
  const evening = new Date(2026, 9, 26, 22, 0).getTime()
  assert.equal(M.pauseUntil(evening, "tomorrow"), new Date(2026, 9, 27, 6, 0).getTime())
  const night = new Date(2026, 9, 27, 3, 0).getTime()
  assert.equal(M.pauseUntil(night, "tomorrow"), new Date(2026, 9, 27, 6, 0).getTime())
  assert.equal(M.pauseUntil(T0, "nonsense"), 0)
})

test("settings are bounded", () => {
  const c = M.config({ farEveryMinutes: 0, blinkSeconds: 99, farSeconds: "x", opacityPercent: 5 })
  assert.equal(c.blinkShowMs, 10000)
  assert.equal(c.farShowMs, 20000)
  assert.equal(c.opacity, 0.2)
  assert.equal(M.config({ dismissOnClick: "true" }).dismissOnClick, true)
})

test("reminders land within the middle half of the free space, centre most likely", () => {
  assert.equal(M.nearCenter(0, 0), -0.5)
  assert.equal(M.nearCenter(1, 1), 0.5)
  assert.equal(M.nearCenter(0.5, 0.5), 0)
  assert.equal(M.config({}).opacity, 0.5)
})

test("fmt", () => {
  assert.equal(M.fmt(45000), "45 s")
  assert.equal(M.fmt(12 * MIN), "12 min")
  assert.equal(M.fmt(65 * MIN), "1 h 5 min")
})
