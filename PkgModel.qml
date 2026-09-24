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

  readonly property var tabs: ["Apps", "Services", "Selection", "Options", "Drafts", "Flakes"]
  property int tab: 0
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
  // Naming cancelled because the user LEFT, not because they pressed ESC.
  // Menu.qml restores the flakeref to the field on ESC, on purpose, so the
  // two cancellations cannot share one notification (#43).
  signal namingAbandoned()

  // ---- what the current tab shows -------------------------------------

  // Searching replaces the list on the tabs where a search makes sense.
  // Apps and Services are a finite catalogue, so there the query filters
  // what is already known rather than asking the index -- instant, and it
  // keeps the enabled state that a search row would not carry.
  readonly property bool searching: query.length > 0
  readonly property bool indexTab: tab === 2 || tab === 3
  readonly property bool flakeTab: tab === 5

  function rows() {
    if (indexTab && searching) return results
    switch (tab) {
      case 0: return filtered(state.apps || [])
      case 1: return filtered(state.services || [])
      case 2: return state.packages || []
      case 3: return state.options || []
      case 4: return state.drafts || []
      case 5: return flakeRows()
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
      var rows = [{ kind: "head", label: inspected.ref }]
      if (inspected.ok === false) {
        rows.push({ kind: "note", label: inspected.message || "could not read that flake" })
        return rows
      }
      var mods = inspected.nixosModules || []
      if (mods.length > 0) {
        for (var i = 0; i < mods.length; i++)
          rows.push({ kind: "module", label: "nixosModules." + mods[i] })
      } else {
        rows.push({ kind: "note", label: "no nixosModules" })
      }
      var pkgs = inspected.packages || []
      if (pkgs.length > 0)
        rows.push({ kind: "note", label: pkgs.length + " package" + (pkgs.length === 1 ? "" : "s") })
      // Named, never drawn as an empty list. `nix flake show` types
      // nixosModules and leaves every other module namespace opaque, so
      // "none" and "cannot tell" are different answers and must read that
      // way.
      var op = inspected.opaque || []
      for (var j = 0; j < op.length; j++)
        rows.push({ kind: "note", label: op[j] + " \u2014 exists, contents cannot be read" })
      rows.push({ kind: "declare", label: "declare this as an input" })
      return rows
    }
    var have = state.flakes || []
    if (have.length === 0) return []
    return have.map(function (f) {
      return { kind: "declared", label: f.name, url: f.url, name: f.name }
    })
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
    if (armedApply !== "") { armedApply = ""; _applyArmTimer.stop(); message = "" }
  }

  // `a` rebuilds the whole system, so it takes two presses, the way
  // SHIFT+RETURN does above: the first says what will happen, the second
  // does it (#27). A stray `a` -- one typed while the keyboard was not
  // where it looked -- once asked for a full apply. "here" is the panel's
  // own apply, "terminal" the SHIFT+A route.
  property string armedApply: ""
  property Timer _applyArmTimer: Timer {
    interval: 5000
    onTriggered: root.disarm()
  }

  // True when this press is the second one and the apply should run.
  function armApply(kind) {
    if (armedApply === kind) {
      armedApply = ""; _applyArmTimer.stop(); message = ""
      return true
    }
    disarm()
    armedApply = kind
    message = (kind === "terminal" ? "SHIFT+A again" : "a again")
      + " to rebuild the system"
      + (kind === "terminal" ? " in a terminal" : "")
      + " \u2014 any other key cancels"
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
    disarm()
    invalidateInspection()
    // A mode must not outlive the tab it belongs to. Left behind, naming
    // swallowed every keystroke into the input name -- setQuery returns
    // early while it is on -- and turned RETURN into a declare against a
    // ref from the tab the user had already left (#43).
    if (naming) { cancelNaming(); namingAbandoned() }
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

  // Search reads on its own channel. Sharing _reader with refresh() meant
  // assigning .command while it was already running -- a no-op in
  // Quickshell -- so a reindex or an apply completing during a search
  // silently dropped its state read, and the footer went on claiming a
  // stale index after a successful rebuild (#43). Every other operation in
  // this file has its own Process for exactly this reason.
  property Process _searcher: Process {
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
    // Naming an input: the field holds the name, not a query or a ref.
    if (naming) { namingName = q; return }
    // On Flakes, a different ref is a different question: RETURN must never
    // act on what the field held before (#29).
    if (flakeTab && inspected !== null && q !== String(inspected.ref)) invalidateInspection()
    query = q
    cursor = 0
    if (indexTab) _debounce.restart()
  }

  function runSearch() {
    if (!indexTab || !searching) { results = []; return }
    // `--` last, so a query starting with a dash is a query (#30).
    _searcher.command = [script, "search",
                         "--kind", tab === 2 ? "pkg" : "opt",
                         "--limit", "60", "--", query]
    _searcher.running = true
  }

  // True when the write started; false when one was already running.
  function write(args) {
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
        // A declared input is the only flake row that acts. The rest are
        // there to be read, and a key that silently did nothing would be
        // worse than one that says why.
        if (row.kind === "declared") write(["flake", "remove", row.name])
        else if (row.kind === "declare") { if (host && host.startNaming) host.startNaming() }
        else if (row.kind === "module")
          message = "paste this into the imports of the host that should have it: "
                  + "inputs." + suggestInputName(inspected ? inspected.ref : "") + "." + row.label
                  + " \u2014 this tool does not know which file that is"
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

  // Ask what a flakeref contains. Nothing is written; `nix flake show`
  // needs no build, and this is the step that exists so a person can look
  // before they commit to running somebody else's build code.
  function inspect() {
    if (!flakeTab || query.length === 0 || inspecting) return
    inspecting = true
    _inspectRun = _inspectToken
    message = "looking at " + query + "\u2026"
    _inspector.command = [script, "flake", "show", query]
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
          root.inspected = JSON.parse(text)
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
      message = "still writing \u2014 try again in a moment"
      return false
    }
    naming = false
    invalidateInspection()
    return true
  }

  // Back to the inspection; the ref to put back in the field.
  function cancelNaming() {
    naming = false
    return namingRef
  }

  function clearInspection() {
    if (inspected === null) return false
    invalidateInspection()
    message = ""
    cursor = 0
    refreshed()
    return true
  }

  function reindex() {
    write(["reindex"])
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
    _applyDone = false
    // Something on screen at once: evaluation can be silent for tens of
    // seconds before the first line of the build arrives.
    applyLog = ["starting rebuild\u2026  ESC stops watching; the build carries on"]
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
