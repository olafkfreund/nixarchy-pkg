import QtQuick
import Quickshell.Io

// Everything the card draws, and the only thing that talks to the machine.
//
// The plugin runs inside the shared Omarchy shell, so a QML error here is a
// degraded desktop rather than a broken panel. That is why all the work
// happens in bin/nixarchy-pkg and this file only reads JSON: a failure over
// there arrives as {"ok":false,"error":...} and is drawn as a message,
// where a failure in here has nowhere to go.
//
// Nothing is predicted. Every write re-reads the state the adapter reports
// rather than assuming the toggle went the way it was asked, because the
// nixarchy writers refuse things -- an unfree package under a policy that
// forbids it, an id that drifted out of the catalogue -- and a panel that
// assumed success would draw a lie.
QtObject {
  id: root

  // The surface that owns this model; it provides close().
  property var host: null

  // The adapter sits next to this file, so the plugin works from wherever
  // it was installed without putting anything on $PATH.
  readonly property string script:
    Qt.resolvedUrl("bin/nixarchy-pkg").toString().replace(/^file:\/\//, "")

  readonly property var tabs: ["Apps", "Services", "Selection", "Options", "Drafts", "Flakes", "Queue"]
  property int tab: 0
  // The number a tab label carries, or "" for none. Same rule as the bar badge.
  function tabCount(i) {
    if (i === 2) return state && state.packages ? String(state.packages.length) : ""
    if (i === 6) return queued > 0 ? String(queued)
                      : (queued === -1 && queueError ? "?" : "")
    return ""
  }
  readonly property string tabName: tabs[tab]

  // What the catalogue tabs draw, straight from `state`.
  property var state: ({})
  // What the search tabs draw, from `search`. Kept apart from `state` so
  // that typing a query never disturbs what is known about the selection.
  property var results: []
  property string query: ""

  // The Flakes tab. `inspected` is what `flake show` last answered about
  // a flakeref, kept apart from `state` the way `results` is kept apart
  // from it for search: one is what the machine has, the other is what
  // was asked about something it does not have yet.
  property var inspected: null
  property bool inspecting: false
  property string _inspectAs: ""
  property var pendingDeclare: null

  property int cursor: 0
  // -1 is "not known": no answer yet, or the last one was an error. 0 is
  // the truth that nothing is queued, and the two must not be confused.
  property int queued: -1
  property var pendingData: null
  property string queueError: ""
  property var checkResult: null
  property bool checkRunning: false
  property string detailText: ""
  // "" | "reading" | "armed". The pins an apply sends are frozen from a
  // fresh read at arming time, so what is built is what was shown.
  property string armingState: ""
  property string armedKind: ""
  property var armedPins: ({})
  property string armedFingerprint: ""
  property int _pendingWant: 0
  property int _pendingRun: 0
  property int _armWant: 0
  property bool _pendingAgain: false
  property bool _readerAgain: false
  property bool _readerAbsorbed: true
  property bool _optionsAgain: false
  property bool _optionsAbsorbed: true
  property bool _searchAgain: false
  property bool _searchAbsorbed: true
  // False from a pending run's start until its answer is absorbed, so a
  // rerun never starts before the answer it follows (exit and stdout come
  // in either order).
  property bool _pendingAbsorbed: true
  // A check's answer counts only while its run is the current one; check()
  // and cancelCheck() both move _checkToken on.
  property int _checkToken: 0
  property int _checkRun: 0
  property string _afterCheck: ""
  property var _deferredArgs: []
  property bool neverApplied: false
  property bool indexStale: false
  // Where the option list came from: "flake" (the host's own flake, read by
  // `options refresh`), "system" (the NixOS manual: today's index), or ""
  // before any answer. Kept like indexStale.
  property string optionsSource: ""
  property bool optionsStale: false
  property string optionsError: ""
  readonly property bool optionsReading: _optionsRefresh.running || reindexing
  readonly property string optionsStatus: {
    if (optionsReading) return "options: reading your flake\u2026"
    if (optionsError !== "") return "options: " + optionsError
    if (optionsSource === "system") return "options: system manual"
    if (optionsSource === "flake" && optionsStale) return "options: your flake (stale)"
    return ""
  }
  // One automatic refresh per panel session for a stale cache found on opening.
  property bool _optionsAuto: false
  property var index: null
  property bool busy: false
  property bool reindexing: false
  property bool _reindexAnswered: false
  property string message: ""

  // The package a SHIFT+RETURN has been pressed once for. Arming is
  // deliberately a property of a NAME, not of the cursor: the danger is
  // arming on one row and committing on another, so the confirm compares
  // the name back rather than trusting the cursor to have stayed put.
  // disarm() is called from everything that moves the list, and the
  // comparison is the belt to its braces.
  property string armedChannel: ""

  // The log of a running apply, as lines. Plain text throughout: this is a
  // build log and whatever it contains is external.
  property var applyLog: []
  property bool applying: false
  // Whether the card is showing the log, which is not the same question as
  // whether a build is running. Detaching stops watching; it does not stop
  // the build, and the two were conflated -- ESC cleared the lines and left
  // an empty pane that still swallowed every key.
  property bool logDetached: false
  readonly property bool showingLog: !logDetached && (applying || applyLog.length > 0)

  // Not "stateChanged": `state` is a property, so Qt generates that signal
  // itself and declaring it again shadows the one bindings listen to.
  signal refreshed()
  // Naming cancelled because the user LEFT, not because they pressed ESC.
  // Menu.qml restores the flakeref to the field on ESC, on purpose, so the
  // two cancellations cannot share one notification (#43).
  signal namingAbandoned()
  // The terminal apply really started (it may wait for a running check).
  signal terminalStarted()

  // ---- what the current tab shows -------------------------------------

  // Searching replaces the list on the tabs where a search makes sense.
  // Apps and Services are a finite catalogue, so there the query filters
  // what is already known rather than asking the index -- instant, and it
  // keeps the enabled state that a search row would not carry.
  readonly property bool searching: query.trim().length > 0
  readonly property bool indexTab: tab === 2 || tab === 3
  readonly property bool flakeTab: tab === 5
  readonly property bool queueTab: tab === 6

  function rows() {
    if (indexTab && searching) return results
    switch (tab) {
      case 0: return catalogueRows(state.apps || [], "apps.nix")
      case 1: return catalogueRows(state.services || [], "services.nix")
      case 2: return state.packages || []
      case 3: return state.options || []
      case 4: return state.drafts || []
      case 5: return flakeRows()
      case 6: return queueRows()
    }
    return []
  }

  // The Flakes tab draws one of two things, and never a mix: what is
  // declared, or what a flakeref turned out to contain. `kind` says which
  // sort of row it is, because they answer to different keys -- a declared
  // input can be removed, an inspected one can be declared, and the lines
  // that are only there to be read answer to neither.
  function flakeRows() {
    if (naming)
      return [{ kind: "note",
                label: "declare " + namingRef + " as inputs." + namingName
                     + " \u2014 RETURN declares, ESC goes back" }]
    if (inspected !== null) {
      var rows = [{ kind: "head", label: inspected.declaredAs
                    ? "inputs." + inspected.declaredAs + " = " + inspected.ref : inspected.ref }]
      if (inspected.ok === false) {
        rows.push({ kind: "note", label: inspected.message || "could not read that flake" })
        return rows
      }
      var mods = inspected.nixosModules || []
      if (mods.length > 0) {
        for (var i = 0; i < mods.length; i++)
          rows.push({ kind: "module", name: mods[i], label: (inspected.declaredAs ? "inputs." + inspected.declaredAs + "." : "") + "nixosModules." + mods[i] })
      } else {
        rows.push({ kind: "note", label: "no nixosModules" })
      }
      var pkgs = inspected.packages || []
      for (var p = 0; p < pkgs.length; p++)
        rows.push({ kind: "package", name: pkgs[p], label: pkgs[p] + " (package)" })
      var overlays = inspected.overlays || []
      for (var o = 0; o < overlays.length; o++)
        rows.push({ kind: "overlay", name: overlays[o], label: overlays[o] + " (overlay)" })
      if (pkgs.length === 0 && inspected.otherCount > 0)
        rows.push({ kind: "note", label: inspected.otherCount + " packages for other systems, none for this one" })
      // Named, never drawn as an empty list. `nix flake show` types
      // nixosModules and leaves every other module namespace opaque, so
      // "none" and "cannot tell" are different answers and must read that
      // way.
      var op = inspected.opaque || []
      for (var j = 0; j < op.length; j++)
        rows.push({ kind: "note", label: op[j] + " \u2014 exists, contents cannot be read" })
      if (!inspected.declaredAs)
        rows.push({ kind: "declare", label: "declare this as an input" })
      return rows
    }
    var have = state.flakes || []
    if (state.flakeDir === undefined) return []   // no answer yet
    var out = [{ kind: "head", label: "flake: " + state.flakeDir }]
    if (state.flakeFound === false)
      out.push({ kind: "note", label: "no flake.nix here. The panel and nixarchy-apply both use"
                + " NIXARCHY_FLAKE (programs.nixarchy.flake sets it); it must be set in the"
                + " session the shell runs in, not only in a terminal." })
    if (state.flakesStale)
      out.push({ kind: "note", label: "a declared input is missing from flake.lock -- the next apply locks it" })
    return out.concat(have.map(function (f) {
      return { kind: "declared", label: f.name, name: f.name, url: f.url,
               mine: f.mine, follows: f.follows, locked: f.locked,
               flake: f.flake, inspectable: f.inspectable }
    }))
  }

  // The Queue tab. The model builds every text; the view only draws it.
  function queueRows() {
    var out = []
    if (queueError) {
      out.push({ kind: "note", text: queueError, path: null, detail: "" })
      return out
    }
    var cr = checkResult
    if (cr) {
      var t
      if (cr.verdict === "evaluates") {
        t = "evaluates \u2713"
        if (cr.dryRun)
          t += " -- " + cr.dryRun.build + " to build, " + cr.dryRun.fetch
             + " to fetch (" + cr.dryRun.downloadMiB + " MiB)"
        if (cr.dryRunError) t += " -- dry run: " + cr.dryRunError
        var bl = cr.blocked || []
        for (var b = 0; b < bl.length; b++)
          t += " -- apply will stop: " + (bl[b].label || bl[b]) + " was edited in the flake"
      } else if (cr.verdict === "fails") {
        t = "fails: " + (cr.summary || "")
        if (cr.at) t += " (" + cr.at.file + (cr.at.line !== null && cr.at.line !== undefined ? ":" + cr.at.line : "") + ", as checked)"
      } else if (cr.verdict === "superseded") {
        t = "superseded -- press c again"
      } else {
        t = "could not check: " + (cr.reason || "")
      }
      out.push({ kind: "check", verdict: cr.verdict, text: t, path: null, detail: cr.error || cr.reason || "" })
    } else if (checkRunning) {
      out.push({ kind: "check", verdict: "running", text: "checking\u2026 (about a minute) -- ESC cancels", path: null, detail: "" })
    }
    var pd = pendingData
    if (!pd) return out
    var files = pd.files || []
    var i
    for (i = 0; i < files.length; i++) {
      var f = files[i]
      if (f.conflict === "overwrite")
        out.push({ kind: "conflict", path: null, detail: f.hunk || "",
                   text: f.label + " was edited in the flake -- apply will keep a copy and overwrite it" })
      else if (f.conflict === "blocks")
        out.push({ kind: "conflict", path: null, detail: f.hunk || "",
                   text: f.label + " was edited in the flake -- apply will stop" })
    }
    if (pd.writing === true)
      out.push({ kind: "writing", path: null, detail: "",
                 text: "a write is in progress or was interrupted -- the queue may be out of date" })
    var verbs = { on: "on", off: "off", added: "added", removed: "removed", modified: "changed" }
    var changes = pd.changes || []
    for (i = 0; i < changes.length; i++) {
      var c = changes[i]
      var name = String(c.marker).replace(/^[^:]*:/, "")
      var where = c.file + ".nix" + (typeof c.lineNo === "number" ? ":" + c.lineNo : "")
      var live = (c.change === "on" || c.change === "added" || c.change === "modified")
      out.push({ kind: "change", detail: c.line || "",
                 text: name + " " + (verbs[c.change] || c.change) + " (" + where + ")",
                 path: live && pd.sources && pd.sources[c.file] ? pd.sources[c.file] : null })
    }
    for (i = 0; i < files.length; i++) {
      var g = files[i]
      if (g.explained !== false) continue
      var what = g.status === "new" ? "new"
               : g.status === "dropped" ? "no longer imported"
               : g.unmarked > 0 ? g.unmarked + " lines changed"
               : "whitespace or comments changed"
      out.push({ kind: "file", text: g.label + ": " + what, detail: g.hunk || "",
                 path: g.status === "dropped" ? null : (g.path || null) })
    }
    var dr = (pd.unpinned && pd.unpinned.drafts) || []
    out.push({ kind: "note", path: null, detail: "",
               text: "not pinned: the flake's own files" + (dr.length > 0 ? ", and drafts: " + dr.join(", ") : "") })
    return out
  }

  function filtered(list) {
    if (!searching) return list
    var words = query.trim().toLowerCase().split(/\s+/)
    return list.filter(function (r) {
      var hay = (String(r.id || "") + " " + String(r.label || "") + " "
                 + String(r.category || "")).toLowerCase()
      return words.every(function (w) { return hay.indexOf(w) >= 0 })
    })
  }

  // Each row gains `section`, the header it is drawn under. Grouped by
  // category in first-seen order, file order within a group: a ListView
  // section is drawn at every change of value, so headers A, B, A would
  // otherwise show A twice. Settings rows go last: they configure an app
  // and cannot be turned on themselves.
  function catalogueRows(list, file) {
    // Object.create(null): a category called "constructor" must not find
    // Object.prototype's.
    var f = filtered(list), order = [], groups = Object.create(null), conf = []
    f.forEach(function (r) {
      if (r.settings === true) {
        conf.push(Object.assign({}, r, { section: "settings \u2014 edit in " + file }))
        return
      }
      var c = r.category || "other"
      if (!groups[c]) { groups[c] = []; order.push(c) }
      groups[c].push(Object.assign({}, r, { section: c }))
    })
    var out = []
    order.forEach(function (c) { out = out.concat(groups[c]) })
    return out.concat(conf)
  }

  function rowAt(i) {
    var list = rows()
    return (i >= 0 && i < list.length) ? list[i] : null
  }

  readonly property int count: rows().length
  // Whatever shrank the rows -- a cancelled check, naming, a filter -- the
  // cursor must still name a row (#75).
  onCountChanged: if (cursor > Math.max(0, count - 1)) cursor = Math.max(0, count - 1)

  // "remove:<name>" or "update:<name>" while a flake row waits for its
  // second press.
  property string armedFlake: ""

  function disarm() {
    if (armedChannel !== "") { armedChannel = ""; message = "" }
    if (armedFlake !== "") { armedFlake = ""; message = "" }
    if (armingState !== "" || armedKind !== "" || armedApply !== "") {
      armingState = ""; armedKind = ""; armedPins = ({}); armedFingerprint = ""
      armedApply = ""; _applyArmTimer.stop(); message = ""
    }
  }

  // `a` rebuilds the whole system, so it takes two presses, the way
  // SHIFT+RETURN does above (#27). The first press reads the queue afresh
  // and freezes what it will send; the second does it. "here" is the
  // panel's own apply, "terminal" the SHIFT+A route. armedApply mirrors
  // armedKind only while armed, which is what Menu.qml's cancel reads.
  property string armedApply: ""
  property Timer _applyArmTimer: Timer {
    interval: 5000
    onTriggered: root.disarm()
  }

  // True when this press is the confirming one. armedPins stay set for
  // apply() / applyInTerminal() to read, and they disarm().
  function armApply(kind) {
    if (armingState === "armed" && kind === armedKind) {
      _applyArmTimer.stop()
      armingState = ""; armedApply = ""; message = ""
      return true
    }
    if (armingState === "reading") { message = "still reading the queue"; return false }
    disarm()
    armingState = "reading"
    armedKind = kind
    message = "reading the queue\u2026"
    refreshPending()
    _armWant = _pendingWant
    // So a read that never answers cannot leave "reading" up for good.
    _applyArmTimer.restart()
    return false
  }

  function moveCursor(delta) {
    disarm()
    var n = count
    if (n === 0) { cursor = 0; return }
    cursor = Math.max(0, Math.min(n - 1, cursor + delta))
  }

  function setTab(i) {
    var next = Math.max(0, Math.min(tabs.length - 1, i))
    disarm()
    invalidateInspection()
    // A mode must not outlive the tab it belongs to. Left behind, naming
    // swallowed every keystroke into the input name -- setQuery returns
    // early while it is on -- and turned RETURN into a declare against a
    // ref from the tab the user had already left (#43).
    if (naming) { cancelNaming(); namingAbandoned() }
    if (next !== tab) { query = ""; results = [] }
    pendingDeclare = null
    tab = next
    cursor = 0
  }

  // ---- talking to the adapter -----------------------------------------

  // One process for reads, one for writes. Separate, so a slow search
  // cannot swallow the result of a toggle you pressed while it ran.
  property Process _reader: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        root._absorb(text, false)
        root._readerAbsorbed = true
        root._readerRerun()
      }
    }
    onRunningChanged: root._readerRerun()
  }

  // Search reads on its own channel. Sharing _reader with refresh() meant
  // assigning .command while it was already running -- a no-op in
  // Quickshell -- so a reindex or an apply completing during a search
  // silently dropped its state read, and the footer went on claiming a
  // stale index after a successful rebuild (#43). Every other operation in
  // this file has its own Process for exactly this reason.
  property Process _searcher: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        root._absorb(text, false)
        root._searchAbsorbed = true
        root._searchRerun()
      }
    }
    onRunningChanged: root._searchRerun()
  }

  property Process _writer: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        root.busy = false
        root._absorb(text, true)
      }
    }
    // busy is cleared by the answer and by nothing else, so a writer that
    // dies without one used to leave the panel refusing every later write
    // with "still writing" until the menu was reopened (#43).
    onExited: function (code, status) {
      root.busy = false
      if (code !== 0 && root.message === "")
        root.message = "the adapter ended without answering (exit " + code
                     + "); nothing is known to be written"
    }
  }

  // Reindex only writes the cache; its own process leaves the writer free.
  // The answer carries indexStale, so no state read races with _reader.
  property Process _reindexer: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        if (text.length > 0) root._reindexAnswered = true
        root._absorb(text, false)
      }
    }
    onExited: function (code, status) {
      root.reindexing = false
      if (code !== 0 && !root._reindexAnswered)
        root.message = "the index rebuild ended without answering (exit " + code + ")"
    }
  }

  // The `options` object of search and reindex, or `optionsInfo` of state.
  // A refresh failure arrives as {ok:false, error} (reindex carries one).
  function _absorbOptions(o, refreshAnswer) {
    if (o === undefined || o === null || typeof o !== "object") return
    if (o.ok === false) {
      root.optionsError = String(o.error || "could not read the options")
      return
    }
    if (o.source === undefined) return
    root.optionsSource = String(o.source)
    root.optionsStale = o.stale === true
    if (refreshAnswer && o.ok === true) root.optionsError = ""
  }

  // A stale cache found on opening is refreshed once, in the background.
  function _optionsAutoRefresh() {
    if (root._optionsAuto || !root.optionsStale || root.optionsSource !== "flake") return
    root._optionsAuto = true
    root.refreshOptions()
  }

  function refreshOptions() {
    if (_optionsRefresh.running || !_optionsAbsorbed) { _optionsAgain = true; return }
    _optionsAbsorbed = false
    _optionsRefresh.command = [script, "options", "refresh"]
    _optionsRefresh.running = true
  }

  function _optionsRerun() {
    if (!_optionsAgain || _optionsRefresh.running || !_optionsAbsorbed) return
    _optionsAgain = false
    refreshOptions()
  }

  property Process _optionsRefresh: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        var data = null
        try { data = JSON.parse(text) } catch (e) { data = null }
        if (data === null || typeof data !== "object")
          data = { ok: false, error: "could not read the adapter" }
        root._absorbOptions(data, true)
        if (data.ok === true && root.tab === 3 && root.searching) root.runSearch()
        root._optionsAbsorbed = true
        root._optionsRerun()
      }
    }
    onRunningChanged: root._optionsRerun()
  }

  function _absorb(text, isWrite) {
    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      // The adapter answers with an object even when it fails, so
      // unparseable output means it did not run at all.
      root.message = "could not read the adapter"
      return
    }
    // Index facts ride on state, search and reindex answers alike, failed or
    // not; take them before any branch returns.
    if (data.indexStale !== undefined) root.indexStale = data.indexStale
    if (data.index !== undefined) root.index = data.index
    if (isWrite && pendingDeclare
        && (data.ok !== true || data.name !== pendingDeclare.name || data.url !== pendingDeclare.ref))
      pendingDeclare = null
    if (data.ok === false && data.error) {
      root._absorbOptions(data.options, true)
      root.message = String(data.error)
      return
    }
    if (data.rows !== undefined) {
      root.results = data.rows
      root._absorbOptions(data.options)
      root.cursor = 0
      return
    }
    // A state object, from `state` or from any writer -- recognised by
    // carrying the catalogue rather than by which command was run. reindex
    // answers {ok, indexStale, index, message} (and detail on failure), and absorbing
    // that as state emptied every tab until the menu was reopened.
    if (data.apps === undefined) {
      root._absorbOptions(data.options, true)
      if (data.message) root.message = String(data.message)
      if (pendingDeclare && data.ok === true
          && data.name === pendingDeclare.name && data.url === pendingDeclare.ref) {
        var saved = pendingDeclare
        pendingDeclare = null
        if (saved.offers !== null && saved.offers.ok !== false) {
          inspected = Object.assign({}, saved.offers, { declaredAs: data.name })
          cursor = 0
          var mods = saved.offers.nixosModules || []
          if (mods.length > 0) {
            var m = mods.indexOf("default") >= 0 ? "default" : mods[0]
            message = "declared " + data.name + ". To use it, add inputs." + data.name
                    + ".nixosModules." + attrName(m)
                    + " to the imports of the host that should have it -- this tool does not know which file that is"
          }
        }
        if (saved.nonFlake)
          message = "declared " + data.name + " as a non-flake source -- use it as inputs."
                  + data.name + " (a path)"
      }
      if (isWrite) root.refresh()
      return
    }
    root.state = data
    root._absorbOptions(data.optionsInfo)
    root._optionsAutoRefresh()
    if (data.message) root.message = String(data.message)
    if (isWrite) root.refreshPending()
    root.cursor = Math.min(root.cursor, Math.max(0, root.count - 1))
    root.refreshed()
  }

  property Process _pending: Process {
    onExited: root._pendingRerun()
    stdout: StdioCollector {
      onStreamFinished: root._absorbPending(text)
    }
  }

  // Invalidation and arming hang off this answer, not off refreshed():
  // _absorb emits refreshed() before the pending read has returned.
  function _absorbPending(text) {
    _pendingAbsorbed = true
    var data
    try { data = JSON.parse(text) } catch (e) { data = null }
    if (data === null || typeof data !== "object") data = { ok: false }
    if (data.ok === true) {
      pendingData = data
      queued = (typeof data.total === "number") ? data.total : -1
      neverApplied = data.neverApplied === true
      queueError = ""
    } else {
      queued = -1
      queueError = data.error || "could not read the queue"
    }

    if (armingState === "armed" && (data.ok !== true || data.writing === true)) {
      disarm()
      message = data.ok !== true ? queueError : "a write is in progress -- try again in a moment"
    }

    if (checkResult && checkResult.fingerprint && data.fingerprint
        && checkResult.fingerprint !== data.fingerprint)
      checkResult = null

    if (armingState === "reading" && _pendingRun >= _armWant) {
      if (data.ok !== true) {
        disarm()
        message = queueError
      } else if (data.writing === true) {
        disarm()
        message = "a write is in progress -- try again in a moment"
      } else {
        var cr = checkResult
        armedPins = (cr && cr.verdict === "evaluates" && cr.fingerprint === data.fingerprint)
          ? cr.pins : data.pins
        armedFingerprint = data.fingerprint
        armingState = "armed"
        armedApply = armedKind
        var n = 0, fl = data.files || []
        for (var i = 0; i < fl.length; i++) if (fl[i].conflict) n++
        message = (armedKind === "terminal" ? "SHIFT+A again" : "a again")
          + " to rebuild: " + data.total + (data.total === 1 ? " change" : " changes")
          + (n ? " -- " + n + " edited in the flake" : "") + " -- any other key cancels"
        _applyArmTimer.restart()
      }
    } else if (armingState === "armed" && data.fingerprint !== armedFingerprint) {
      disarm()
      message = "the queue changed -- review it again"
    }
    _pendingRerun()
  }

  // Starting a running Process is a no-op, so a read asked for meanwhile
  // runs once this one has both exited and been absorbed.
  function _pendingRerun() {
    if (!_pendingAgain || _pending.running || !_pendingAbsorbed) return
    _pendingAgain = false
    _pendingStart()
  }

  function _pendingStart() {
    _pendingRun = _pendingWant
    _pendingAbsorbed = false
    _pending.command = [script, "pending"]
    _pending.running = true
  }

  function refresh() {
    refreshPending()
    if (_reader.running || !_readerAbsorbed) { _readerAgain = true; return }
    _readerAbsorbed = false
    _reader.command = [script, "state"]
    _reader.running = true
  }

  function _readerRerun() {
    if (!_readerAgain || _reader.running || !_readerAbsorbed) return
    _readerAgain = false
    refresh()
  }

  function refreshPending() {
    _pendingWant++
    if (_pending.running || !_pendingAbsorbed) { _pendingAgain = true; return }
    _pendingStart()
  }

  // ---- the check -------------------------------------------------------

  property Process _check: Process {
    onExited: function (code, status) {
      root.checkRunning = false
      if (root._afterCheck !== "") {
        var after = root._afterCheck
        root._afterCheck = ""
        if (after === "here") root._startApply(root._deferredArgs)
        else root._startTerminal(root._deferredArgs)
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        if (root._checkRun !== root._checkToken) return
        var data = null
        try { data = JSON.parse(text) } catch (e) { data = null }
        if (data === null || typeof data !== "object" || data.ok === false)
          root.checkResult = { verdict: "unknown",
                               reason: (data && data.error) || "the check did not answer" }
        else {
          if (root.pendingData && data.fingerprint
              && (data.verdict === "evaluates" || data.verdict === "fails")
              && data.fingerprint !== root.pendingData.fingerprint)
            data.verdict = "superseded"
          root.checkResult = data
        }
      }
    }
  }

  function check(dry) {
    if (checkRunning || applying) return
    _check.command = dry ? [script, "check", "--dry-run"] : [script, "check"]
    checkResult = null
    checkRunning = true
    _checkRun = ++_checkToken
    _check.running = true
  }

  function cancelCheck() {
    if (!checkRunning) return
    _checkToken++
    checkResult = null
    _check.running = false
  }

  // Typing is debounced, because a keystroke costs a grep over 138k rows
  // and the answer to a half-typed word is never the one wanted.
  property Timer _debounce: Timer {
    interval: 140
    onTriggered: root.runSearch()
  }

  function setQuery(q) {
    disarm()
    // Naming an input: the field holds the name, not a query or a ref.
    if (naming) { namingName = q; return }
    // On Flakes, a different ref is a different question: RETURN must never
    // act on what the field held before (#29).
    if (flakeTab && inspected !== null && (inspected.declaredAs ? q !== "" : q !== String(inspected.ref)))
      invalidateInspection()
    query = q
    cursor = 0
    if (indexTab) _debounce.restart()
  }

  function runSearch() {
    if (!indexTab || !searching) { results = []; return }
    if (_searcher.running || !_searchAbsorbed) { _searchAgain = true; return }
    _searchAbsorbed = false
    // `--` last, so a query starting with a dash is a query (#30).
    _searcher.command = [script, "search",
                         "--kind", tab === 2 ? "pkg" : "opt",
                         "--limit", "60", "--", query]
    _searcher.running = true
  }

  function _searchRerun() {
    if (!_searchAgain || _searcher.running || !_searchAbsorbed) return
    _searchAgain = false
    runSearch()
  }

  // True when the write started; false when one was already running.
  function write(args) {
    if (applying) { message = "an apply is running \u2014 wait for it to finish"; return false }
    if (busy) return false
    busy = true
    message = ""
    _writer.command = [script].concat(args)
    _writer.running = true
    return true
  }

  // ---- the actions a key can reach ------------------------------------

  function activate() {
    disarm()
    var row = rowAt(cursor)
    if (!row) return
    if (indexTab && searching) {
      // A search row is not yet in the selection, so RETURN adds it.
      if (tab === 2) write(["pkg", "add", row.name])
      return
    }
    // A `.settings` row is not an app and has no enable to flip: it is the
    // attrset that configures one, and nixarchy-app-enable rightly refuses
    // it ("'firefox.settings' is not an app id"). Sending it anyway put
    // that refusal on screen as a desktop notification, which is a bug
    // here rather than there.
    if (row.settings === true) {
      root.message = "\u201c" + row.id + "\u201d configures "
        + String(row.id).replace(/\.settings$/, "")
        + " \u2014 edit it in " + (root.state.files ? root.state.files.apps : "apps.nix")
      return
    }
    switch (tab) {
      case 0: write(["toggle", "app", row.id]); break
      case 1: write(["toggle", "service", row.id]); break
      case 2: write(["pkg", "remove", row.attr]); break
      case 3: write(["opt", "remove", row.path]); break
      case 4: write(["draft", "undraft", row.name]); break
      case 5:
        if (row.kind === "declared") inspectRow(row)
        else if (row.kind === "declare") { if (host && host.startNaming) host.startNaming() }
        else if (row.kind === "module" || row.kind === "package" || row.kind === "overlay") {
          var n = attrName(inspected.declaredAs || suggestInputName(inspected.ref))
          var line = row.kind === "module" ? "inputs." + n + ".nixosModules." + attrName(row.name)
                   : row.kind === "package" ? "inputs." + n + ".packages.${pkgs.stdenv.hostPlatform.system}." + attrName(row.name)
                   : "inputs." + n + ".overlays." + attrName(row.name)
          var where = row.kind === "module" ? "the host's imports"
                    : row.kind === "package" ? "environment.systemPackages" : "nixpkgs.overlays"
          message = line + " goes in " + where + " -- this tool does not know which file that is"
        }
        break
    }
  }

  // SHIFT+RETURN on a search row: the same add, from the other channel.
  //
  // Two presses, because the cost is invisible and large -- the two
  // channels share no store paths, so this brings a whole second closure
  // (nixarchy-doctor measures vlc at 1.5 GB). The first press says what
  // will happen; the second does it. Anything that moves the list disarms.
  //
  // It says the licence and broken status are NOT KNOWN rather than
  // showing the row's flags, because those flags are about a different
  // package: nixarchy-pkg-add probes the system's own nixpkgs (its :246)
  // and its other-channel branch returns before the flag block (:301-318)
  // -- so for this request there is no evidence, and borrowing the
  // default channel's would be a confident lie.
  function addFromOtherChannel() {
    if (!indexTab || !searching || tab !== 2) return
    var row = rowAt(cursor)
    if (!row) return

    var mine = state.channel || "custom"
    var other = mine === "unstable" ? "stable"
              : mine === "stable"   ? "unstable" : ""

    // Nothing to arm: there is no "other" channel to name, and sending a
    // plain add from here would be the RETURN key under another name.
    if (other === "") {
      message = row.name + " -- cannot tell which channel this machine follows from "
        + (state.flakeDir || "the flake") + "/flake.nix, so there is no \"other\" channel"
        + " to add from -- RETURN adds it from this one"
      return
    }

    if (armedChannel === row.name) {
      armedChannel = ""
      write(["pkg", "add", "--" + other, row.name])
      return
    }

    armedChannel = row.name
    message = row.name + " from the " + other + " channel."
      + " It brings its own closure: the two channels share no store paths,"
      + " even at the same version. unfree and broken are not known for that"
      + " channel. SHIFT+RETURN again to add it."
  }

  // Two presses, like the channel add: the first says what will happen,
  // the second does it. Anything that moves the list disarms.
  function armFlake(kind) {            // "remove" | "update"
    var row = rowAt(cursor)
    if (!flakeTab || !row || row.kind !== "declared") return false
    var key = kind + ":" + row.name
    if (armedFlake === key) {
      armedFlake = ""; message = ""
      var started = write(kind === "remove" ? ["flake", "remove", row.name]
                                            : ["flake", "update", row.name])
      if (!started && busy && !applying)
        message = "another change is still running -- try again"
      return started
    }
    disarm()
    if (kind === "update" && (row.follows || row.locked === false)) {
      message = row.name + (row.follows ? " follows " + row.follows + "; update that one"
                                        : " is not locked yet; the next apply locks it")
      return false
    }
    if (kind === "remove" && row.mine === false) {
      message = row.name + " was not declared by this tool -- edit flake.nix to remove it"
      return false
    }
    armedFlake = key
    message = kind === "remove"
      ? "remove " + row.name + " from flake.nix? SPACE again removes it, any other key cancels"
      : "update " + row.name + "? It changes what the next apply builds"
        + ((row.name === "nixpkgs" || row.name === "nixarchy") ? " -- the whole system" : "")
        + ". u again updates it, any other key cancels"
    return true
  }

  function keyCancelsFlakeArm(key) {
    return armedFlake !== "" && key !== Qt.Key_Space
      && !(armedFlake.indexOf("update:") === 0 && key === Qt.Key_U)
      && key !== Qt.Key_Shift && key !== Qt.Key_Control
      && key !== Qt.Key_Alt && key !== Qt.Key_Meta
      && key !== Qt.Key_Super_L && key !== Qt.Key_Super_R
  }

  // Ask what a flakeref contains. Nothing is written; `nix flake show`
  // needs no build, and this is the step that exists so a person can look
  // before they commit to running somebody else's build code.
  function inspect() {
    if (!flakeTab || query.length === 0) return
    if (_inspector.running) { message = "still reading the last flake -- try again in a moment"; return }
    pendingDeclare = null
    _inspectAs = ""
    inspecting = true
    _inspectRun = _inspectToken
    message = "looking at " + query + "\u2026"
    _inspector.command = [script, "flake", "show", query]
    _inspector.running = true
  }

  function inspectRow(row) {
    if (row.flake === false) { message = "not a flake: nothing to inspect"; return }
    if (row.follows) { message = "follows " + row.follows + ": inspect that one"; return }
    if (row.inspectable === false) { message = "cannot inspect this kind of input from here"; return }
    if (_inspector.running) { message = "still reading the last flake -- try again in a moment"; return }
    pendingDeclare = null
    _inspectAs = row.name
    inspecting = true
    _inspectRun = _inspectToken
    message = "looking at " + row.url + "\u2026"
    _inspector.command = [script, "flake", "show", row.url]
    _inspector.running = true
  }

  // Bumped whenever what is on screen stops being the question an
  // inspection in flight was asked: ESC, a tab change, an edited ref. A
  // result for an older question is dropped rather than drawn (#29).
  property int _inspectToken: 0
  property int _inspectRun: -1

  function invalidateInspection() {
    _inspectToken++
    inspected = null
    inspecting = false
  }

  property Process _inspector: Process {
    // No answer at all -- the process could not start, or died -- must not
    // leave "looking at…" up for good.
    onExited: function (exitCode, exitStatus) {
      Qt.callLater(function () {
        if (!root.inspecting || root._inspectRun !== root._inspectToken) return
        root.inspecting = false
        root.message = "could not read what that flake exposes"
      })
    }
    stdout: StdioCollector {
      onStreamFinished: {
        if (root._inspectRun !== root._inspectToken) return
        root.inspecting = false
        try {
          var r = JSON.parse(text)
          if (root._inspectAs && r.ok === true) r.declaredAs = root._inspectAs
          root.inspected = r
          root.message = ""
        } catch (e) {
          root.inspected = null
          root.message = "could not read what that flake exposes"
        }
        root.cursor = 0
        root.refreshed()
      }
    }
  }

  // The import line is shown, never written. Which host file it belongs
  // in is the part this cannot know -- flake_base guesses a directory
  // from the hostname, which is neither the nixosConfigurations attribute
  // nor an import site -- so it says so rather than guessing.
  //
  // The input's name is suggested from the ref's STRUCTURE, never its last
  // segment: the last segment of github:owner/repo/release-25.05 is the
  // branch, and that is what used to be written into the system flake as
  // the input's name (#29). The person confirms or edits it first.
  function suggestInputName(ref) {
    var r = String(ref || "").replace(/[?#].*$/, "").replace(/\/+$/, "")
    var m = r.match(/^(?:github|gitlab|sourcehut):([^\/]+)\/([^\/]+)/)
    var name = m ? m[2] : r.replace(/^.*[\/:]/, "")
    name = name.replace(/\.git$/, "").replace(/\.(?:tar\.gz|tar\.xz|tar\.bz2|tgz|zip)$/, "")
    name = name.replace(/[^A-Za-z0-9_-]/g, "-")
    if (/^[0-9]/.test(name)) name = "_" + name
    return name
  }

  function attrName(s) {
    s = String(s)
    return /^[A-Za-z_][A-Za-z0-9_'-]*$/.test(s) ? s
      : '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\$\{/g, "\\${") + '"'
  }

  // Name mode: RETURN on "declare this as an input" puts the suggestion in
  // the field for the person to confirm or change. The adapter validates
  // whatever comes back; this only pre-fills it.
  property bool naming: false
  property string namingRef: ""
  property string namingName: ""

  // The suggestion to pre-fill, or null when there is nothing to name.
  function beginNaming() {
    if (inspected === null || inspected.ok === false) return null
    namingRef = String(inspected.ref)
    namingName = suggestInputName(namingRef)
    naming = true
    return namingName
  }

  // True when the declaration started. A refusal (busy) keeps the name and
  // the inspection, where clearing them used to lose both.
  function declareAs(name) {
    if (!write(["flake", "add", String(name), namingRef])) {
      // write() has already said why when an apply is running.
      if (!applying) message = "still writing \u2014 try again in a moment"
      return false
    }
    pendingDeclare = { name: String(name), ref: namingRef, offers: inspected, nonFlake: false }
    naming = false
    invalidateInspection()
    return true
  }

  // Back to the inspection; the ref to put back in the field.
  function cancelNaming() {
    pendingDeclare = null
    naming = false
    return namingRef
  }

  function clearInspection() {
    pendingDeclare = null
    if (inspected === null) return false
    invalidateInspection()
    message = ""
    cursor = 0
    refreshed()
    return true
  }

  // The footer's index line. `now` in ms (Date.now()), passed in so a test
  // can fix it.
  function indexLine(now) {
    var ix = index
    if (!ix) return "index stale \u2014 r to rebuild"
    if (ix.status === "missing") return "no search index \u2014 r to build it"
    var parts = [typeof ix.builtAt === "number"
                 ? "index built " + _ago(now / 1000 - ix.builtAt)
                 : "index stale"]
    // The key first: the footer elides from the end, and the key is what to do.
    parts.push("r to rebuild")
    if (ix.changed && ix.changed.length > 0) parts.push(_names(ix.changed) + " changed")
    return parts.join(" \u2014 ")
  }
  function _ago(s) {
    s = Math.max(0, s)
    if (s < 60) return "just now"
    var m = Math.floor(s / 60)
    if (m < 60) return m + (m === 1 ? " minute" : " minutes") + " ago"
    var h = Math.floor(m / 60)
    if (h < 48) return h + (h === 1 ? " hour" : " hours") + " ago"
    var d = Math.floor(h / 24)
    return d + (d === 1 ? " day" : " days") + " ago"
  }
  function _names(n) {
    if (n.length === 1) return n[0]
    if (n.length === 2) return n[0] + " and " + n[1]
    return n[0] + " and " + (n.length - 1) + " more"
  }

  function reindex() {
    if (reindexing) { message = "already rebuilding the index"; return false }
    reindexing = true
    _reindexAnswered = false
    message = "rebuilding the search index and reading your flake (may take several minutes)"
    _reindexer.command = [script, "reindex"]
    _reindexer.running = true
    return true
  }

  // The one command here that changes the machine, and only ever on an
  // explicit key. Output is a build log: streamed as lines and drawn as
  // plain text, then one line wrapping the result in `nixarchyPkgApply`.
  property bool _applyDone: false

  function _logLine(text) {
    var log = root.applyLog.slice()
    log.push(text)
    // A rebuild prints a great deal and the card shows the end of it.
    if (log.length > 400) log = log.slice(log.length - 400)
    root.applyLog = log
  }

  property Process _apply: Process {
    stdout: SplitParser {
      onRead: function (line) {
        var trimmed = String(line)
        var done = null
        if (trimmed.indexOf("{\"nixarchyPkgApply\"") === 0) {
          try {
            var parsed = JSON.parse(trimmed).nixarchyPkgApply
            // Only the adapter's own record ends the apply. The log is a
            // build's output and nixpkgs builds print JSON; a line of it
            // shaped like a result used to end the apply, drop the rest of
            // the log and report a result nobody produced (#26).
            if (parsed && typeof parsed.ok === "boolean") done = parsed
          } catch (e) { done = null }
        }
        if (done !== null) {
          root._applyDone = true
          root.applying = false
          root.message = String(done.message || "")
          // Into the log as well as the footer: the footer is hidden while
          // the log is up, so the result was never seen (#26).
          root._logLine(done.ok ? "\u2014 applied \u2014"
                                : "\u2014 failed: " + String(done.message || "") + " \u2014")
          root.refresh()
          // The flake just changed: read its options again, off to the side.
          if (done.ok) root.refreshOptions()
          return
        }
        root._logLine(trimmed)
      }
    }
    // An adapter that ended without a record -- it could not start, or
    // died before streaming -- would otherwise leave `applying` set for
    // good. Exit and the last read are not ordered, so this waits a tick
    // for a record that may still be on its way.
    onExited: function (exitCode, exitStatus) {
      Qt.callLater(function () {
        if (root._applyDone) return
        root.applying = false
        root._logLine("\u2014 the apply ended without a result; see above \u2014")
      })
    }
  }

  function apply() {
    // Not while a writer is still running: nixarchy-apply would copy the
    // files as they were before the write, and the writer would then land
    // exactly that change back in the queue after the apply reported done.
    if (applying || busy) {
      message = busy ? "still writing \u2014 try again in a moment" : ""
      return
    }
    var args = [script, "apply"]
    for (var p in armedPins) args.push("--pin", p + "=" + armedPins[p])
    disarm()
    _applyDone = false
    // Something on screen at once: evaluation can be silent for tens of
    // seconds before the first line of the build arrives.
    applyLog = ["starting rebuild\u2026  ESC stops watching; the build carries on"]
    logDetached = false
    applying = true
    message = ""
    if (checkRunning) { _afterCheck = "here"; _deferredArgs = args; cancelCheck() }
    else _startApply(args)
  }

  function _startApply(args) {
    _apply.command = args
    _apply.running = true
  }

  // The same apply, in a terminal. The route for a host with no polkit
  // agent to answer pkexec, and for any apply that asks something this
  // panel cannot show -- it is a full terminal, so nixarchy-apply's own
  // questions and nh's password both have somewhere to go.
  property Process _applyTerm: Process {
    command: ["omarchy-launch-floating-terminal-with-presentation", "nixarchy-apply"]
  }

  // True when the terminal was started; the caller closes the menu only then,
  // so a refusal stays on screen.
  function applyInTerminal() {
    if (applying) { message = "an apply is running \u2014 wait for it to finish"; return false }
    if (busy) { message = "still writing \u2014 try again in a moment"; return false }
    var cmd = ["omarchy-launch-floating-terminal-with-presentation", "nixarchy-apply"]
    for (var p in armedPins) cmd.push("--expect-sha256=" + p + "=" + armedPins[p])
    disarm()
    if (checkRunning) { _afterCheck = "terminal"; _deferredArgs = cmd; cancelCheck() }
    else _startTerminal(cmd)
    return true
  }

  function _startTerminal(cmd) {
    _applyTerm.command = cmd
    _applyTerm.running = true
    terminalStarted()
  }

  // Detaching from the log leaves the build running: it is elevating,
  // downloading and switching a system, and killing it half way through is
  // never what someone reaching for ESC meant.
  function detachFromLog() {
    logDetached = true
  }
}
