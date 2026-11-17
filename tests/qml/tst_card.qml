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
import qs.Commons
import qs.Commons as Commons

TestCase {
  name: "CardGeometry"
  when: windowShown

  property var theRows: [
    { id: "two",  section: "Alpha", label: "steam", summary: "Digital distribution platform",
      flags: ["unfree", "curated:steam"],
      preview: "steam  1.0\nctrl-t tries it now\nversion:  1.0" },
    { id: "one",  section: "Beta", label: "one (Terminal)", category: "Terminal",
      summary: "one flag here", flags: ["unfree"], note: "a note" },
    { id: "none", section: "Beta", label: "Gamescope", category: "Game", summary: "no flags here", flags: [] }
  ]
  property var appRows: []
  property var selRows: [
    { attr: "ripgrep", channel: "default", summary: "Utility that combines usability",
      version: "15.2.0", flags: [] },
    { attr: "vlc", channel: "other" },
    { attr: "steam", channel: "default",
      summary: "A very long summary that needs to elide before it reaches the tags at a normal card width",
      version: "1.0", flags: ["unfree", "broken", "curated:steam"] },
    { attr: "nosuchpkg", channel: "default" },
    { attr: "searchrow", flags: ["unfree"], summary: "no channel on a search row" },
    { attr: "version-only", channel: "default", version: "2.0", flags: [] },
    { attr: "openssl_1_1", channel: "default", summary: "an insecure package",
      version: "1.1.1w", flags: ["unfree", "insecure"] },
    { attr: "insecure-search", flags: ["insecure"],
      summary: "a search row, no channel" }
  ]
  // A QtObject, so a test can set tab and cursor and Card sees it change.
  QtObject {
    id: fakeModel
    property var tabs: ["Apps", "Services", "Selection", "Options", "Drafts", "Flakes", "Queue"]
    property int tab: 0
    property int cursor: 0
    property int count: 3
    function rows() { return theRows }
    function rowAt(i) { return (i >= 0 && i < theRows.length) ? theRows[i] : null }
    property bool busy: false
    property bool reindexing: false
    property string selCount: "2"
    property string queueCount: "?"
    function tabCount(i) { return i === 2 ? selCount : i === 6 ? queueCount : "" }
    property bool inspecting: false
    property bool flakeTab: tab === 5
    property string query: ""
    property bool checkRunning: false
    property string message: ""
    property int queued: 0
    property string queueError: ""
    property bool queueTab: false
    property bool indexStale: false
    property string optionsStatus: ""
    property bool optionsError: false
    property var userScope: ({ available: false, reason: "Home Manager part is missing" })
    function indexLine(now) { return "index built 14 days ago \u2014 r to rebuild \u2014 nixpkgs and 4 more changed" }
    property bool neverApplied: false
    property bool showingLog: false
    property string applyLog: ""
    property bool applying: false
  }

  function test_user_badge_and_disabled_reason() {
    compare(card.tagsOf({ attr: "git", scope: "user", flags: [] }), ["user"])
    fakeModel.tab = 2
    theRows = [{ attr: "git", scope: "user" }]
    compare(card.previewText, "Home Manager part is missing")
  }

  Window {
    id: win
    width: 800; height: 400
    visible: true
    Card { id: card; anchors.fill: parent; model: fakeModel }
    // The real model, for #75: the fake's rows binding hid the trigger.
    // Hidden, so it never takes the pointer from the hover tests.
    PkgModel { id: realModel }
    Card { id: realCard; width: 800; height: 400; model: realModel; visible: false }
  }
  Component { id: busyCardComponent; Card {} }

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

  function initTestCase() { appRows = theRows.slice() }

  function init() {
    theRows = appRows
    fakeModel.count = 3
    fakeModel.tab = 0
    fakeModel.cursor = 0
    fakeModel.busy = false
    fakeModel.reindexing = false
    fakeModel.inspecting = false
    fakeModel.checkRunning = false
    win.width = 800
    Style.reduceMotion = true
    fakeModel.selCount = "2"
    fakeModel.queueCount = "?"
    // Park the pointer off every row and tab so hover does not leak between tests.
    mouseMove(win.contentItem, win.width - 2, win.height - 2)
  }

  function test_option_rows_show_state_type_and_current_line() {
    var original = theRows
    try {
      theRows = [
        { kind: "opt", name: "x.y", summary: "Set option", type: "boolean",
          set: true, current: "true" },
        { kind: "opt", name: "x.z", summary: "Scaffold option", type: "string",
          set: false, current: "x.z = ;" }
      ]
      fakeModel.tab = 3
      fakeModel.count = 2
      var lv = find(card, "QQuickListView")
      tryCompare(lv, "count", 2)
      for (var i = 0; i < 2; i++) {
        var d = lv.itemAtIndex(i)
        verify(d !== null)
        var row = find(d, "QQuickRow")
        compare(row.children[0].text, i === 0 ? "\u25a0" : "\u25a1")
        var summary = elidables(d, []).pop().text
        verify(summary.indexOf(theRows[i].summary + "  \u00b7  " + theRows[i].type) >= 0)
        if (i === 0) compare(summary.indexOf("  =  true") >= 0, true)
        else compare(summary.indexOf("=") < 0, true, "a scaffold row shows no =")
      }
    } finally {
      theRows = original
      fakeModel.count = 3
    }
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

  function useRows(rows, tab) {
    theRows = rows
    fakeModel.count = rows.length
    fakeModel.tab = tab
    tryCompare(find(card, "QQuickListView"), "count", rows.length)
  }

  function tagsIn(delegate) {
    var tags = []
    function walk(it) {
      if (!it) return
      if (it.hasOwnProperty("text") && it.parent && it.parent.hasOwnProperty("tone"))
        tags.push({ text: it.text, color: it.parent.tone })
      for (var i = 0; i < it.children.length; i++) walk(it.children[i])
    }
    walk(delegate)
    return tags
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

  // Header Texts in the list's contentItem whose text is a section name.
  function headers(lv) {
    var n = 0, kids = lv.contentItem.children
    for (var i = 0; i < kids.length; i++)
      if (kids[i].visible && (kids[i].text === "Alpha" || kids[i].text === "Beta")) n++
    return n
  }

  function test_sections_on_catalogue_tabs_only() {
    var lv = find(card, "QQuickListView")
    fakeModel.tab = 0
    tryCompare(lv, "count", 3)
    wait(50)
    compare(headers(lv), 2, "Alpha and Beta, once each")
    // The real model hands the list a new array on every tab change; the
    // fake's rows() reads theRows, so reassign it to match.
    fakeModel.tab = 2; theRows = theRows.slice()
    wait(50)
    compare(headers(lv), 0, "no headers on the Selection tab")
    fakeModel.tab = 0; theRows = theRows.slice()
    wait(50)
    compare(headers(lv), 2, "and they come back")
  }

  function footerText() {
    var out = []
    function walk(it) {
      if (!it) return
      if (it.hasOwnProperty("text") && /queue|queued|working/.test(String(it.text))) out.push(String(it.text))
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

  function test_index_line_fits_between_neighbours() {
    fakeModel.indexStale = true
    fakeModel.queued = 12
    fakeModel.neverApplied = true
    fakeModel.busy = false
    card.model = null; card.model = fakeModel
    try {
      for (var width of [800, 480]) {
        win.width = width
        wait(0)
        var texts = elidables(card, [])
        var queue = null, index = null, keys = null
        for (var i = 0; i < texts.length; i++) {
          if (texts[i].text.indexOf("12 changes queued") === 0) queue = texts[i]
          if (texts[i].text.indexOf("index built 14 days ago") === 0) index = texts[i]
          if (texts[i].text === "? keys   a apply   esc close") keys = texts[i]
        }
        verify(queue !== null && index !== null && keys !== null, "footer texts at " + width + " px")
        compare(queue.parent, index.parent)
        compare(index.parent, keys.parent)
        verify(queue.x + queue.width <= index.x, "queue and index overlap at " + width + " px")
        verify(index.x + index.width <= keys.x, "index and keys overlap at " + width + " px")
      }
    } finally {
      fakeModel.indexStale = false
      fakeModel.queued = 0
      fakeModel.neverApplied = false
      win.width = 800
    }
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

  function centreOf(item) {
    return item.mapToItem(win.contentItem, item.width / 2, item.height / 2)
  }

  function test_row_hover_does_not_move_the_cursor() {
    var lv = find(card, "QQuickListView")
    tryCompare(lv, "count", 3)
    var p = centreOf(lv.itemAtIndex(1))
    mouseMove(win.contentItem, p.x, p.y)
    verify(Qt.colorEqual(lv.itemAtIndex(1).color, card.hoverBackground))
    verify(Qt.colorEqual(lv.itemAtIndex(0).color, Commons.Color.menu.selectedBackground))
    compare(fakeModel.cursor, 0)
  }

  function test_resting_row_is_clear() {
    var lv = find(card, "QQuickListView")
    tryCompare(lv, "count", 3)
    var c = lv.itemAtIndex(1).color
    compare(c.a, 0)
    // The same hue as the selection, not "transparent": a fade from black passes through grey.
    verify(Qt.colorEqual(Qt.rgba(c.r, c.g, c.b, 1), Qt.rgba(card.selectedBg.r, card.selectedBg.g, card.selectedBg.b, 1)))
  }

  function test_tab_hover() {
    var tabs = find(card, "QQuickRow")
    var item = tabs.children[1]
    var text = null
    for (var i = 0; i < item.children.length; i++)
      if (item.children[i].hasOwnProperty("text")) { text = item.children[i]; break }
    var p = centreOf(item)
    mouseMove(win.contentItem, p.x, p.y)
    verify(Qt.colorEqual(text.color, card.fg))
    compare(fakeModel.tab, 0)
  }

  function test_busy_rule_moves() {
    var segment = byName(card, "busySegment")
    Style.reduceMotion = false
    for (var field of ["busy", "reindexing", "inspecting", "checkRunning"]) {
      fakeModel[field] = true
      verify(segment.visible, field + " shows the segment")
      verify(card.busyAnimating, field + " starts motion")
      fakeModel[field] = false
      verify(!segment.visible, field + " hides the segment")
      verify(!card.busyAnimating, field + " stops motion")
    }
  }

  function test_busy_rule_rests_while_hidden() {
    Style.reduceMotion = false
    fakeModel.busy = true
    verify(card.busyAnimating)
    win.visible = false
    try {
      verify(!card.busyAnimating)
    } finally {
      win.visible = true
    }
    verify(card.busyAnimating)
  }

  function test_busy_rule_without_motion() {
    var segment = byName(card, "busySegment")
    var base = byName(card, "busyRuleBase")
    fakeModel.busy = true
    verify(!segment.visible)
    verify(!card.busyAnimating)
    verify(Qt.colorEqual(base.color, Commons.Color.menu.selectedText))
    compare(base.opacity, 1)
    verify(footerText().indexOf("working\u2026") >= 0)
  }

  function test_busy_segment_follows_width() {
    var segment = byName(card, "busySegment")
    card.busyProgress = 0.5
    compare(segment.x, 320)
    win.width = 400
    wait(0)
    compare(segment.x, 160)
  }

  function test_busy_card_created_busy() {
    fakeModel.busy = true
    Style.reduceMotion = false
    var second = busyCardComponent.createObject(win.contentItem,
                                                 { width: 800, height: 400, model: fakeModel })
    verify(second !== null)
    try {
      wait(0)
      compare(byName(second, "busySegment").parent.width, 800)
      verify(second.busyAnimating)
    } finally {
      second.destroy()
    }
  }

  function tabLabel(i) {
    var item = find(card, "QQuickRow").children[i]
    for (var k = 0; k < item.children.length; k++)
      if (item.children[k].hasOwnProperty("text")) return item.children[k]
    return null
  }

  function test_tab_labels_carry_counts() {
    compare(tabLabel(2).text, "Selection 2")
    compare(tabLabel(6).text, "Queue ?")
    compare(tabLabel(0).text, "Apps")
    var sel = tabLabel(2), q = tabLabel(6)
    fakeModel.selCount = "5"
    fakeModel.queueCount = ""
    compare(sel.text, "Selection 5")
    compare(q.text, "Queue")
  }

  function test_header_fits() {
    var h = byName(card, "header")
    verify(h.implicitWidth <= h.width, "the tab row fits at 800 px")
  }

  function test_flake_head_only_shows_hint() {
    var savedRows = theRows
    try {
      fakeModel.tab = 5
      fakeModel.query = "github:owner/repo"
      theRows = [{ kind: "head", label: "flake: /f" }]
      var hint = byName(card, "emptyHint")
      tryCompare(hint, "visible", true)
      compare(hint.text, "RETURN to see what \u201cgithub:owner/repo\u201d offers")
      fakeModel.inspecting = true
      compare(hint.text, "looking at \u201cgithub:owner/repo\u201d\u2026")
    } finally {
      fakeModel.inspecting = false
      fakeModel.query = ""
      fakeModel.tab = 0
      theRows = savedRows
    }
  }

  // ---- #75: the row you see selected is the row a key acts on ----------

  function realList() { return find(realCard, "QQuickListView") }
  function st(n, onIndex) {
    var apps = []
    for (var i = 0; i < n; i++)
      apps.push({ id: "a" + i, label: "App " + i, category: "Utility", kind: "app", enabled: i === onIndex })
    return JSON.stringify({ ok: true, apps: apps, services: [], packages: [], options: [], drafts: [] })
  }
  function pend(o) {
    var d = { ok: true, total: 1, count: 1, fingerprint: "f1", writing: false,
              pins: { apps: "aa" }, files: [], changes: [], sources: {}, unpinned: { drafts: [] } }
    for (var k in o) d[k] = o[k]
    return JSON.stringify(d)
  }
  function changes3() {
    return [ { marker: "app:a", change: "on", file: "apps", line: "x" },
             { marker: "app:b", change: "on", file: "apps", line: "y" },
             { marker: "app:c", change: "on", file: "apps", line: "z" } ]
  }
  // Run body with the real card shown; always hide it again.
  function withReal(n, body) {
    realCard.visible = true
    try {
      realModel.busy = false
      realModel.checkResult = null
      realModel.checkRunning = false
      realModel.inspected = null
      realModel.setTab(0)
      realModel._reader.deliver(st(n, -1))
      tryCompare(realList(), "count", n)
      body()
    } finally {
      realModel.inspected = null
      realModel.checkResult = null
      realModel.checkRunning = false
      realModel.pendingData = null
      realModel.setTab(0)
      realCard.visible = false
    }
  }
  // Key order differs between a ListView's modelData and the model's own row.
  function canon(r) {
    if (r === null) return "null"
    var out = []
    Object.keys(r).sort().forEach(function (k) { out.push(k + "=" + JSON.stringify(r[k])) })
    return out.join("|")
  }
  function agree() {
    compare(realList().currentIndex, realModel.cursor, "list follows the cursor")
    compare(canon(realCard.currentRow), canon(realModel.rowAt(realModel.cursor)),
            "preview shows the cursor row")
  }
  function writeAndAnswer(args, answer) {
    verify(realModel.write(args))
    realModel._writer.deliver(answer)
    wait(50)
  }

  function test_real_write_same_count() {
    withReal(6, function () {
      realModel.cursor = 2
      writeAndAnswer(["toggle", "app", "a2"], st(6, 2))
      compare(realModel.cursor, 2)
      compare(realList().currentIndex, 2)
      verify(realCard.currentRow.enabled === true, "the new content")
      agree()
    })
  }

  function test_real_write_shrinks_without_crossing() {
    withReal(6, function () {
      realModel.cursor = 2
      writeAndAnswer(["toggle", "app", "a2"], st(4, 2))
      compare(realList().currentIndex, 2)
      agree()
    })
  }

  function test_real_move_during_write() {
    withReal(6, function () {
      realModel.cursor = 2
      verify(realModel.write(["toggle", "app", "a2"]))
      realModel.cursor = 4
      realModel._writer.deliver(st(6, 2))
      wait(50)
      compare(realModel.cursor, 4)
      compare(realList().currentIndex, 4)
      agree()
    })
  }

  function queueSetup() {
    realModel.setTab(6)
    realModel._pending.deliver(pend({ changes: changes3() }))
    wait(50)
  }

  function test_real_queue_check_row_goes_on_cancel() {
    withReal(6, function () {
      queueSetup()
      realModel.checkResult = null
      realModel.checkRunning = true
      realModel.cursor = realModel.count - 1
      wait(50)
      realModel.cancelCheck()
      realModel._check.finish(143)
      wait(50)
      verify(realModel.cursor < realModel.count, "cursor names a row")
      agree()
    })
  }

  function test_real_queue_check_row_goes_on_invalidate() {
    withReal(6, function () {
      queueSetup()
      realModel.checkRunning = false
      realModel.checkResult = { verdict: "evaluates", fingerprint: "f1" }
      realModel.cursor = realModel.count - 1
      wait(50)
      realModel._pending.deliver(pend({ changes: changes3(), fingerprint: "f2" }))
      wait(50)
      verify(realModel.cursor < realModel.count, "cursor names a row")
      agree()
    })
  }

  function test_real_naming_shrinks_flakes() {
    withReal(6, function () {
      realModel.setTab(5)
      realModel.inspected = { ref: "github:o/r", ok: true, nixosModules: ["a", "b", "c"] }
      realModel.cursor = realModel.count - 1
      verify(realModel.cursor >= 2)
      wait(50)
      realModel.beginNaming()
      wait(50)
      compare(realModel.cursor, 0)
      agree()
    })
  }

  function test_real_shrink_below_cursor() {
    withReal(6, function () {
      realModel.cursor = 5
      writeAndAnswer(["toggle", "app", "a5"], st(4, -1))
      compare(realModel.cursor, 3)
      compare(realList().currentIndex, 3)
      agree()
    })
  }

  function test_real_empty_and_refill() {
    withReal(6, function () {
      realModel.cursor = 2
      realModel._reader.deliver(st(0, -1))
      wait(50)
      realModel._reader.deliver(st(6, -1))
      tryCompare(realList(), "count", 6)
      wait(50)
      compare(realModel.cursor, 0)
      agree()
    })
  }

  function test_real_tab_change_resets() {
    withReal(6, function () {
      realModel.cursor = 3
      realModel.setTab(1)
      realModel.setTab(0)
      compare(realModel.cursor, 0)
      compare(realList().currentIndex, 0)
    })
  }

  // #66: an interrupted write's reason is long; the footer status must stop
  // where the key hints begin.
  function test_long_queue_error_does_not_run_under_the_hints() {
    fakeModel.queued = -1
    fakeModel.queueError = "an earlier write was interrupted (/home/u/.config/nixarchy/apps.nix). To put back what was there before, run: /nix/store/x/bin/nixarchy-pkg recover. If the files look right as they are, run: /nix/store/x/bin/nixarchy-pkg recover --discard."
    try {
      var st = byName(card, "queueStatus"), h = byName(card, "hints")
      verify(st && h)
      var stRight = st.mapToItem(card, st.width, 0).x
      var hLeft = h.mapToItem(card, 0, 0).x
      verify(stRight <= hLeft, "status ends at " + stRight + ", hints start at " + hLeft)
      verify(st.truncated, "the long reason is elided")
    } finally {
      fakeModel.queueError = ""
      fakeModel.queued = 0
    }
  }

  // #62 + #66: the options status sits between the queue status and the hints.
  function test_options_status_between_queue_and_hints() {
    fakeModel.queued = -1
    fakeModel.queueError = "an earlier write was interrupted (/home/u/.config/nixarchy/apps.nix). To put back what was there before, run: nixarchy-pkg recover."
    fakeModel.optionsStatus = "options: system manual"
    try {
      var st = byName(card, "queueStatus"), os = byName(card, "optionsStatus"), h = byName(card, "hints")
      verify(st && os && h && os.visible)
      var right = function (it) { return it.mapToItem(card, it.width, 0).x }
      var left = function (it) { return it.mapToItem(card, 0, 0).x }
      verify(right(st) <= left(os), "queue status ends before the options status")
      verify(right(os) <= left(h), "options status ends before the hints")
    } finally {
      fakeModel.queueError = ""; fakeModel.queued = 0; fakeModel.optionsStatus = ""
    }
  }

  function test_stale_index_and_options_status_do_not_overlap() {
    fakeModel.queued = 0
    fakeModel.indexStale = true
    fakeModel.optionsStatus = "options: reading your flake\u2026"
    try {
      var q = byName(card, "queueStatus"), s = byName(card, "indexAge")
      var o = byName(card, "optionsStatus"), h = byName(card, "hints")
      verify(q && s && o && h && s.visible && o.visible)
      var right = function (it) { return it.mapToItem(card, it.width, 0).x }
      var left = function (it) { return it.mapToItem(card, 0, 0).x }
      verify(right(q) <= left(s), "queue ends before stale index")
      verify(right(s) <= left(o), "stale index ends before options")
      verify(right(o) <= left(h), "options end before hints")
    } finally {
      fakeModel.indexStale = false
      fakeModel.optionsStatus = ""
    }
  }

  // #66 + #69: queue status, index age and key hints share one footer line
  // and never overlap, even with a long reason on the left.
  function test_footer_parts_do_not_overlap() {
    fakeModel.queued = -1
    fakeModel.queueError = "an earlier write was interrupted (/home/u/.config/nixarchy/apps.nix). To put back what was there before, run: nixarchy-pkg recover."
    fakeModel.indexStale = true
    try {
      var st = byName(card, "queueStatus"), ia = byName(card, "indexAge"), h = byName(card, "hints")
      verify(st && ia && h && ia.visible)
      var right = function (it) { return it.mapToItem(card, it.width, 0).x }
      var left = function (it) { return it.mapToItem(card, 0, 0).x }
      verify(right(st) <= left(ia), "queue status ends before the index age")
      verify(right(ia) <= left(h), "index age ends before the hints")
    } finally {
      fakeModel.queueError = ""; fakeModel.queued = 0; fakeModel.indexStale = false
    }
  }

  function test_selection_rows_draw_a_channel_tag() {
    useRows(selRows, 2)
    var lv = find(card, "QQuickListView")
    compare(tagsIn(lv.itemAtIndex(0)).map(t => t.text), ["default"])
    compare(tagsIn(lv.itemAtIndex(1)).map(t => t.text), ["other"])
    compare(tagsIn(lv.itemAtIndex(2)).map(t => t.text),
            ["unfree", "broken", "curated:steam", "default"])
  }

  function test_version_leads_the_second_column() {
    useRows(selRows, 2)
    var lv = find(card, "QQuickListView")
    function second(i) {
      var ts = elidables(lv.itemAtIndex(i), [])
      return ts[ts.length - 1].text
    }
    compare(second(0), "15.2.0  Utility that combines usability")
    compare(second(5), "2.0  ")
    compare(second(1), "")
    compare(second(3), "")
  }

  function test_channel_tag_tones() {
    useRows(selRows, 2)
    var lv = find(card, "QQuickListView")
    var other = tagsIn(lv.itemAtIndex(1))[0]
    var steam = tagsIn(lv.itemAtIndex(2))
    verify(other !== undefined, "other has a tag")
    compare(steam.length, 4, "steam has three flags and its channel")
    verify(Qt.colorEqual(other.color, Commons.Color.accent), "other uses accent")
    verify(Qt.colorEqual(steam[0].color, Commons.Color.accent), "unfree stays accent")
    verify(Qt.colorEqual(steam[1].color, Commons.Color.urgent), "broken stays urgent")
    verify(Qt.colorEqual(steam[3].color, card.dim), "default stays dim")
  }

  function test_insecure_tag_is_urgent() {
    useRows(selRows, 2)
    var lv = find(card, "QQuickListView")
    var sel = tagsIn(lv.itemAtIndex(6))
    var srch = tagsIn(lv.itemAtIndex(7))
    compare(sel.map(t => t.text), ["unfree", "insecure", "default"])
    verify(Qt.colorEqual(sel[1].color, Commons.Color.urgent), "insecure selection row is urgent")
    compare(srch.map(t => t.text), ["insecure"])
    verify(Qt.colorEqual(srch[0].color, Commons.Color.urgent), "insecure search row is urgent")
  }

  function test_selection_summary_fits_at_800_and_700() {
    failOnWarning(/Binding loop detected/)
    useRows(selRows, 2)
    var lv = find(card, "QQuickListView")
    for (var width of [800, 700]) {
      win.width = width
      wait(150)
      for (var i = 0; i < selRows.length; i++) {
        var delegate = lv.itemAtIndex(i)
        verify(delegate !== null, "delegate " + i + " at " + width + " px")
        var row = find(delegate, "QQuickRow")
        var ts = elidables(delegate, [])
        var summary = ts[ts.length - 1]
        verify(summary.x + summary.width - row.width <= 0.5,
               "row " + i + " fits at " + width + " px")
        verify(summary.width >= 0, "row " + i + " has nonnegative width")
      }
    }
  }

  function test_search_row_on_selection_has_no_channel_tag() {
    useRows(selRows, 2)
    var lv = find(card, "QQuickListView")
    compare(tagsIn(lv.itemAtIndex(4)).map(t => t.text), ["unfree"])
    useRows(appRows, 0)
    compare(tagsIn(lv.itemAtIndex(0)).map(t => t.text), ["unfree", "curated:steam"])
    compare(tagsIn(lv.itemAtIndex(1)).map(t => t.text), ["unfree"])
    compare(tagsIn(lv.itemAtIndex(2)).length, 0)
  }

  function test_bare_row_is_quiet() {
    failOnWarning(/.?/)
    useRows(selRows, 2)
    var delegate = find(card, "QQuickListView").itemAtIndex(3)
    var ts = elidables(delegate, [])
    compare(ts[ts.length - 1].text, "")
  }

  // #62 + #66 + #69: queue status, index age, options status and hints all
  // at once, at 800 px, with a long queue reason: none overlaps another.
  function test_all_four_footer_parts_do_not_overlap() {
    fakeModel.queued = -1
    fakeModel.queueError = "an earlier write was interrupted (/home/u/.config/nixarchy/apps.nix). To put back what was there before, run: nixarchy-pkg recover."
    fakeModel.indexStale = true
    fakeModel.optionsStatus = "options: reading your flake\u2026"
    try {
      var q = byName(card, "queueStatus"), ia = byName(card, "indexAge")
      var o = byName(card, "optionsStatus"), h = byName(card, "hints")
      verify(q && ia && o && h && ia.visible && o.visible)
      var right = function (it) { return it.mapToItem(card, it.width, 0).x }
      var left = function (it) { return it.mapToItem(card, 0, 0).x }
      verify(right(q) <= left(ia), "queue ends before the index age")
      verify(right(ia) <= left(o), "index age ends before the options status")
      verify(right(o) <= left(h), "options status ends before the hints")
    } finally {
      fakeModel.queueError = ""; fakeModel.queued = 0
      fakeModel.indexStale = false; fakeModel.optionsStatus = ""
    }
  }
}
