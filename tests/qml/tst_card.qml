// Card's layout, measured rather than looked at.
//
// The Window is NOT optional and must not be removed. Item.visible is
// EFFECTIVE visibility, so every item under a bare TestCase reads false --
// and Row lays out by effective visibility, skipping the flags wrapper
// while Card's own `flags.visible ? 3 : 2` reads its binding as true. That
// disagreement is a phantom 10px overflow at every flag count, which cost
// most of a session to chase and was very nearly filed as a defect in the
// #45 fix it was actually exonerating (#51).
import QtQuick
import QtQuick.Window
import QtTest

TestCase {
  name: "CardGeometry"
  when: windowShown

  property var theRows: [
    { id: "two",  label: "steam", summary: "Digital distribution platform",
      flags: ["unfree", "curated:steam"] },
    { id: "one",  label: "one",   summary: "one flag here", flags: ["unfree"] },
    { id: "none", label: "plain", summary: "no flags here", flags: [] }
  ]
  property var fakeModel: ({
    tabs: ["S"], tab: 0, cursor: 0, count: 3,
    rows: function () { return theRows },
    busy: false, message: "", queued: 0, indexStale: false, neverApplied: false,
    showingLog: false, applyLog: "", applying: false
  })

  Window {
    id: win
    width: 800; height: 400
    visible: true
    Card { id: card; anchors.fill: parent; model: fakeModel }
  }

  function find(item, cls) {
    if (!item) return null
    if (item.toString().indexOf(cls) === 0) return item
    for (var i = 0; i < item.children.length; i++) {
      var r = find(item.children[i], cls); if (r) return r
    }
    return null
  }
  function elidables(item, out) {
    if (!item) return out
    if (item.hasOwnProperty("elide") && item.hasOwnProperty("text")) out.push(item)
    for (var i = 0; i < item.children.length; i++) elidables(item.children[i], out)
    return out
  }

  // The property, not the formula. Reproducing the width expression would
  // only assert this file's copy of it (#51).
  function test_summary_fits_its_row_at_every_flag_count() {
    var lv = find(card, "QQuickListView")
    verify(lv !== null, "the card must have a list")
    tryCompare(lv, "count", 3)
    wait(150)

    for (var n = 0; n < 3; n++) {
      var d = lv.itemAtIndex(n)
      verify(d !== null, "delegate " + n + " must be realised")
      var row = find(d, "QQuickRow")
      var ts = elidables(d, [])
      var summary = ts[ts.length - 1]
      var overflow = summary.x + summary.width - row.width
      verify(overflow <= 0.5,
             theRows[n].flags.length + " flag(s): the summary must fit its row"
             + " -- overflows by " + overflow.toFixed(1))
      verify(summary.width >= 0,
             theRows[n].flags.length + " flag(s): width must never be negative")
    }
  }
}
