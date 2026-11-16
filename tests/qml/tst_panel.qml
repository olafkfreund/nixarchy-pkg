import QtQuick
import QtTest

TestCase {
  name: "Panel"
  when: windowShown
  width: 300; height: 100
  visible: true

  Component { id: panelC; Panel {} }
  property var p: null
  property var pending: null
  property var summon: null
  property var button: null

  function proc(word) {
    for (var i = 0; i < p.data.length; i++) {
      var c = p.data[i]
      if (c && c.command !== undefined && c.deliver && String(c.command).indexOf(word) >= 0) return c
    }
    return null
  }
  function init() {
    if (p) p.destroy()
    p = panelC.createObject(this)
    pending = proc("pending"); summon = proc("toggle")
    button = p.children[0]
  }
  function answer(o) { pending.deliver(typeof o === "string" ? o : JSON.stringify(o)) }

  function test_loads_unknown() {
    compare(p.queued, -1)
    compare(button.tooltipText, "nixarchy · reading the queue…")
  }
  function test_ok_total() {
    answer({ ok: true, total: 3, neverApplied: false })
    compare(p.queued, 3); compare(p.queueError, ""); compare(p.neverApplied, false)
    compare(button.tooltipText, "3 changes waiting for a rebuild")
  }
  function test_one_change_never_applied() {
    answer({ ok: true, total: 1, neverApplied: true })
    compare(button.tooltipText, "1 change waiting for a rebuild\nthis machine has never run nixarchy-apply")
  }
  function test_zero() {
    answer({ ok: true, total: 0 })
    compare(p.queued, 0); compare(button.tooltipText, "nixarchy · nothing queued")
  }
  function test_ok_without_total() {
    answer({ ok: true })
    compare(p.queued, -1); compare(button.tooltipText, "nixarchy · reading the queue…")
  }
  function test_not_ok() {
    answer({ ok: false, error: "no apps.nix" })
    compare(p.queued, -1); compare(p.queueError, "no apps.nix")
    compare(button.tooltipText, "nixarchy · queue unknown: no apps.nix")
    answer({ ok: false, error: "" })
    compare(p.queueError, "could not read the queue")
    answer({ ok: false })
    compare(p.queueError, "could not read the queue")
  }
  function test_malformed() {
    answer("not json")
    compare(p.queued, -1); compare(p.queueError, "could not read the queue")
  }
  function test_failure_after_a_count_forgets_it() {
    answer({ ok: true, total: 4 }); answer({ ok: false, error: "x" })
    compare(p.queued, -1)
    answer({ ok: true, total: 4 }); answer("not json")
    compare(p.queued, -1)
  }
  function test_recovers() {
    answer({ ok: false, error: "x" }); answer({ ok: true, total: 2 })
    compare(p.queued, 2); compare(p.queueError, "")
  }
  function test_buttons() {
    pending.running = false; summon.running = false
    button.pressed(Qt.LeftButton)
    compare(summon.running, true); compare(pending.running, false)
    summon.running = false
    button.pressed(Qt.MiddleButton)
    compare(pending.running, true); compare(summon.running, false)
    pending.running = false
    button.pressed(Qt.RightButton)
    compare(pending.running, false); compare(summon.running, false)
  }
}
