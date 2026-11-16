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
      flags: ["unfree", "curated:steam"],
      preview: "steam  1.0\nctrl-t tries it now\nversion:  1.0" },
    { id: "one",  label: "one (Terminal)", category: "Terminal",
      summary: "one flag here", flags: ["unfree"], note: "a note" },
    { id: "none", label: "Gamescope", category: "Game", summary: "no flags here", flags: [] }
  ]
  // A QtObject, so a test can set tab and cursor and Card sees it change.
  QtObject {
    id: fakeModel
    property var tabs: ["S"]
    property int tab: 0
    property int cursor: 0
    property int count: 3
    function rows() { return theRows }
    property bool busy: false
    property string message: ""
    property int queued: 0
    property string queueError: ""
    property bool queueTab: false
    property bool indexStale: false
    property bool neverApplied: false
    property bool showingLog: false
    property string applyLog: ""
    property bool applying: false
  }

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
  function byName(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var r = byName(item.children[i], name); if (r) return r
    }
    return null
  }
  function textOf(item) {
    var ts = elidables(item, [])
    return ts.length ? ts[0].text : ""
  }
  function elidables(item, out) {
    if (!item) return out
    if (item.hasOwnProperty("elide") && item.hasOwnProperty("text")) out.push(item)
    for (var i = 0; i < item.children.length; i++) elidables(item.children[i], out)
    return out
  }

  function init() {
    fakeModel.tab = 0
    fakeModel.cursor = 0
    win.width = 800
  }

  // Every row is checked at both layouts: with the icon column and without.
  function checkSummaries() {
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
             "tab " + fakeModel.tab + ", row " + n + ": the summary must fit"
             + " its row -- overflows by " + overflow.toFixed(1))
    }
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

  function footerText() {
    var out = []
    function walk(it) {
      if (!it) return
      if (it.hasOwnProperty("text") && /queue|queued/.test(String(it.text))) out.push(String(it.text))
      for (var i = 0; i < it.children.length; i++) walk(it.children[i])
    }
    walk(card)
    return out.join("|")
  }

  // #60: unknown is not zero.
  function test_footer_says_when_the_queue_is_unknown() {
    fakeModel.queued = -1; fakeModel.queueError = "boom"
    card.model = null; card.model = fakeModel
    verify(footerText().indexOf("queue unknown -- boom") >= 0, footerText())
    fakeModel.queueError = ""
    card.model = null; card.model = fakeModel
    verify(footerText().indexOf("reading queue") >= 0, footerText())
    verify(footerText().indexOf("nothing queued") < 0, footerText())
    fakeModel.queued = 0
    card.model = null; card.model = fakeModel
    verify(footerText().indexOf("nothing queued") >= 0, footerText())
  }

  function test_dim_is_fg_at_lower_alpha() {
    compare(card.dim.r, card.fg.r)
    compare(card.dim.g, card.fg.g)
    compare(card.dim.b, card.fg.b)
    verify(card.dim.a < 1, "dim must be translucent, not darker")
  }

  function test_summary_fits_with_and_without_icons() {
    var lv = find(card, "QQuickListView")
    fakeModel.tab = 0
    checkSummaries()
    var img = find(lv.itemAtIndex(0), "QQuickImage")
    verify(img.visible, "tab 0 must reserve the icon column")
    verify(img.source.toString() !== "", "a found icon is drawn")
    // A missing icon must not be requested at all: image://icon/ answers
    // with a checkerboard that reports itself Ready.
    compare(find(lv.itemAtIndex(1), "QQuickImage").source.toString(), "")
    fakeModel.tab = 2
    checkSummaries()
    verify(!find(lv.itemAtIndex(0), "QQuickImage").visible,
           "tab 2 must not reserve the icon column")
  }

  // Apps and Services rows carry no preview; the pane composes one, with
  // a blank line between groups and none for a missing field.
  function test_preview_composed_for_app_rows() {
    var pane = byName(card, "preview")
    fakeModel.cursor = 1
    tryCompare(pane, "visible", true)
    compare(textOf(pane), "one (Terminal)\n\na note", "a category the label shows is not repeated")
    fakeModel.cursor = 2
    tryCompare(pane, "visible", true)
    compare(textOf(pane), "Gamescope\nGame", "a category that is only a substring is kept")
  }

  function test_preview_shows_and_filters() {
    var pane = byName(card, "preview")
    verify(pane !== null, "the card must have a preview pane")
    tryCompare(pane, "visible", true)
    var t = textOf(pane)
    verify(t.indexOf("version:") >= 0, "the preview text must be drawn")
    verify(t.indexOf("ctrl-") < 0, "key hints must be filtered out")
  }

  function test_preview_sits_beside_the_list() {
    var pane = byName(card, "preview")
    var lv = find(card, "QQuickListView")
    tryCompare(pane, "visible", true)
    verify(pane.x >= lv.x + lv.width, "the pane must not overlap the list")
    verify(pane.x + pane.width <= card.width + 0.5, "the pane must fit the card")
  }

  function test_preview_hidden_when_narrow() {
    var pane = byName(card, "preview")
    tryCompare(pane, "visible", true)
    win.width = 700
    tryCompare(pane, "visible", false)
  }

  function test_preview_hidden_without_text() {
    failOnWarning(/Binding loop detected/)
    var pane = byName(card, "preview")
    fakeModel.tab = 2
    fakeModel.cursor = 2
    tryCompare(pane, "visible", false)
  }

  function test_selection_tab_has_no_binding_loop() {
    failOnWarning(/Binding loop detected/)
    var scope = byName(card, "scope")
    fakeModel.tab = 2
    verify(scope.height > 0)
    win.width = 300; wait(0)
    var narrow = scope.height
    win.width = 800; wait(0)
    verify(narrow > scope.height, "the line wraps at 300 px")
    fakeModel.tab = 0
    compare(scope.height, 0)
  }
}
