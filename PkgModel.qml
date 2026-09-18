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

  readonly property var tabs: ["Apps", "Services", "Packages", "Options", "Drafts"]
  property int tab: 0
  readonly property string tabName: tabs[tab]

  // What the catalogue tabs draw, straight from `state`.
  property var state: ({})
  // What the search tabs draw, from `search`. Kept apart from `state` so
  // that typing a query never disturbs what is known about the selection.
  property var results: []
  property string query: ""

  property int cursor: 0
  property int queued: 0
  property bool neverApplied: false
  property bool indexStale: false
  property bool busy: false
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

  // ---- what the current tab shows -------------------------------------

  // Searching replaces the list on the tabs where a search makes sense.
  // Apps and Services are a finite catalogue, so there the query filters
  // what is already known rather than asking the index -- instant, and it
  // keeps the enabled state that a search row would not carry.
  readonly property bool searching: query.length > 0
  readonly property bool indexTab: tab === 2 || tab === 3

  function rows() {
    if (indexTab && searching) return results
    switch (tab) {
      case 0: return filtered(state.apps || [])
      case 1: return filtered(state.services || [])
      case 2: return state.packages || []
      case 3: return state.options || []
      case 4: return state.drafts || []
    }
    return []
  }

  function filtered(list) {
    if (!searching) return list
    var q = query.toLowerCase()
    return list.filter(function (r) {
      return String(r.id || "").toLowerCase().indexOf(q) >= 0
          || String(r.label || "").toLowerCase().indexOf(q) >= 0
          || String(r.category || "").toLowerCase().indexOf(q) >= 0
    })
  }

  function rowAt(i) {
    var list = rows()
    return (i >= 0 && i < list.length) ? list[i] : null
  }

  readonly property int count: rows().length

  function disarm() {
    if (armedChannel !== "") { armedChannel = ""; message = "" }
  }

  function moveCursor(delta) {
    disarm()
    var n = count
    if (n === 0) { cursor = 0; return }
    cursor = Math.max(0, Math.min(n - 1, cursor + delta))
  }

  function setTab(i) {
    disarm()
    tab = Math.max(0, Math.min(tabs.length - 1, i))
    cursor = 0
    if (indexTab && searching) runSearch()
  }

  // ---- talking to the adapter -----------------------------------------

  // One process for reads, one for writes. Separate, so a slow search
  // cannot swallow the result of a toggle you pressed while it ran.
  property Process _reader: Process {
    stdout: StdioCollector {
      onStreamFinished: root._absorb(text, false)
    }
  }

  property Process _writer: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        root.busy = false
        root._absorb(text, true)
      }
    }
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
    if (data.ok === false && data.error) {
      root.message = String(data.error)
      return
    }
    if (data.rows !== undefined) {
      root.results = data.rows
      if (data.indexStale !== undefined) root.indexStale = data.indexStale
      root.cursor = 0
      return
    }
    // A state object, from `state` or from any writer -- recognised by
    // carrying the catalogue rather than by which command was run. reindex
    // answers {ok, indexStale, message} and nothing else, and absorbing
    // that as state emptied every tab until the menu was reopened.
    if (data.apps === undefined) {
      if (data.message) root.message = String(data.message)
      if (isWrite) root.refresh()
      return
    }
    root.state = data
    if (data.indexStale !== undefined) root.indexStale = data.indexStale
    if (data.message) root.message = String(data.message)
    if (isWrite) root.refreshPending()
    root.cursor = Math.min(root.cursor, Math.max(0, root.count - 1))
    root.refreshed()
  }

  property Process _pending: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data.ok) {
            root.queued = data.count || 0
            root.neverApplied = data.neverApplied === true
          }
        } catch (e) { /* a count is not worth a message */ }
      }
    }
  }

  function refresh() {
    _reader.command = [script, "state"]
    _reader.running = true
    refreshPending()
  }

  function refreshPending() {
    _pending.command = [script, "pending"]
    _pending.running = true
  }

  // Typing is debounced, because a keystroke costs a grep over 138k rows
  // and the answer to a half-typed word is never the one wanted.
  property Timer _debounce: Timer {
    interval: 140
    onTriggered: root.runSearch()
  }

  function setQuery(q) {
    disarm()
    query = q
    cursor = 0
    if (indexTab) _debounce.restart()
  }

  function runSearch() {
    if (!indexTab || !searching) { results = []; return }
    _reader.command = [script, "search", query,
                       "--kind", tab === 2 ? "pkg" : "opt",
                       "--limit", "60"]
    _reader.running = true
  }

  function write(args) {
    if (busy) return
    busy = true
    message = ""
    _writer.command = [script].concat(args)
    _writer.running = true
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

    if (armedChannel === row.name) {
      armedChannel = ""
      // No flag when the channel is unknown: the writer says the same
      // thing better, and refuses if it turns out to be the one we are on.
      write(other === "" ? ["pkg", "add", row.name]
                         : ["pkg", "add", "--" + other, row.name])
      return
    }

    armedChannel = row.name
    message = row.name + (other === ""
        ? " \u2014 cannot tell which channel this machine follows, so I cannot"
          + " tell you which one this would come from."
        : " from the " + other + " channel.")
      + " It brings its own closure: the two channels share no store paths,"
      + " even at the same version. unfree and broken are not known for that"
      + " channel. SHIFT+RETURN again to add it."
  }

  function reindex() {
    write(["reindex"])
  }

  // The one command here that changes the machine, and only ever on an
  // explicit key. Output is a build log: streamed as lines and drawn as
  // plain text, with the adapter's single JSON object on the last line.
  property Process _apply: Process {
    stdout: SplitParser {
      onRead: function (line) {
        var trimmed = String(line)
        var done = null
        if (trimmed.indexOf("{") === 0) {
          try {
            var parsed = JSON.parse(trimmed)
            // Shape-checked, not merely parsed. The log is a build's own
            // output and nixpkgs builds print JSON; a line of it that
            // happened to parse would otherwise end the apply, drop the
            // rest of the log and report a result nobody produced.
            if (parsed && typeof parsed.ok === "boolean"
                && typeof parsed.exit === "number") done = parsed
          } catch (e) { done = null }
        }
        if (done !== null) {
          root.applying = false
          root.message = String(done.message || "")
          root.refresh()
          return
        }
        var log = root.applyLog.slice()
        log.push(trimmed)
        // A rebuild prints a great deal and the card shows the end of it.
        if (log.length > 400) log = log.slice(log.length - 400)
        root.applyLog = log
      }
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
    applyLog = []
    logDetached = false
    applying = true
    message = ""
    _apply.command = [script, "apply"]
    _apply.running = true
  }

  // The same apply, in a terminal. The route for a host with no polkit
  // agent to answer pkexec, and for any apply that asks something this
  // panel cannot show -- it is a full terminal, so nixarchy-apply's own
  // questions and nh's password both have somewhere to go.
  property Process _applyTerm: Process {
    command: ["omarchy-launch-floating-terminal-with-presentation", "nixarchy-apply"]
  }

  function applyInTerminal() {
    if (applying) return
    _applyTerm.running = true
  }

  // Detaching from the log leaves the build running: it is elevating,
  // downloading and switching a system, and killing it half way through is
  // never what someone reaching for ESC meant.
  function detachFromLog() {
    logDetached = true
  }
}
