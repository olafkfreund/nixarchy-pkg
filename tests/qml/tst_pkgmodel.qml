// The data layer, driven without a desktop.
//
// Every case here is a defect that shipped, not one invented to look
// thorough (#50). The stubs hand the model a canned answer or a death; the
// assertions are about what the MODEL did with it, never about what a stub
// produced.
import QtQuick
import QtTest

TestCase {
  name: "PkgModel"
  when: windowShown

  PkgModel { id: m }

  function cleanup() {
    m.busy = false
    m.reindexing = false
    m._reindexAnswered = false
    m._reindexer.running = false
    m.applying = false
    m.message = ""
    m._applyTerm.running = false
    if (m.naming) m.cancelNaming()
    m.setTab(0)
    m.queued = -1
    m.pendingData = null
    m.queueError = ""
    m.checkResult = null
    m.checkRunning = false
    m.detailText = ""
    m.disarm()
    m.armingState = ""
    m._pendingWant = 0
    m._pendingRun = 0
    m._armWant = 0
    m._pendingAgain = false
    m._readerAgain = false
    m._readerAbsorbed = true
    m._optionsAgain = false
    m._optionsAbsorbed = true
    m._searchAgain = false
    m._searchAbsorbed = true
    m._pendingAbsorbed = true
    m._checkToken = 0
    m._checkRun = 0
    m._afterCheck = ""
    m._deferredArgs = []
    m.neverApplied = false
    m._pending.running = false
    m._check.running = false
    m._apply.command = []
    m.optionsSource = ""
    m.optionsStale = false
    m.optionsError = ""
    m._optionsAuto = false
    m._optionsRefresh.running = false
    m._optionsRefresh.command = []
    m._reader.running = false
    m._reader.command = []
    m._searcher.running = false
  }

  function pend(o) {
    var d = { ok: true, total: 1, count: 1, fingerprint: "f1", writing: false,
              pins: { apps: "aa" }, files: [], changes: [], sources: {}, unpinned: { drafts: [] } }
    for (var k in o) d[k] = o[k]
    return JSON.stringify(d)
  }

  // #59: a write must not start while an apply holds the lock.
  function test_write_refused_while_applying() {
    m.applying = true
    compare(m.write(["toggle", "app", "x"]), false)
    verify(m.message.indexOf("apply is running") >= 0, "it says why")
    compare(m.busy, false, "and does not become busy")
  }

  // #59: a refused flake declaration keeps the apply's reason.
  function test_declare_during_apply_keeps_the_reason() {
    m.applying = true
    compare(m.declareAs("x"), false)
    verify(m.message.indexOf("apply is running") >= 0, "not 'still writing'")
  }

  // #59: reindex writes only the cache, so an apply does not block it.
  function test_reindex_not_refused_while_applying() {
    m.applying = true
    compare(m.reindex(), true)
    compare(m.reindexing, true)
    compare(m.busy, false, "reindex does not occupy the writer")
  }

  function test_write_during_reindex_starts() {
    compare(m.reindex(), true)
    compare(m.write(["toggle", "app", "x"]), true)
  }

  function test_second_reindex_refused() {
    compare(m.reindex(), true)
    compare(m.reindex(), false)
    compare(m.message, "already rebuilding the index")
  }

  function test_reindex_answer_sets_index_stale() {
    m.indexStale = true
    m._reader.running = false
    m._absorb(JSON.stringify({ok:true, indexStale:false, message:"index rebuilt"}), false)
    compare(m.indexStale, false)
    compare(m._reader.running, false)
  }

  function test_reindex_death_is_reported() {
    m.reindex()
    m._reindexer.finish(1)
    compare(m.reindexing, false)
    verify(m.message.indexOf("ended without answering") >= 0)
  }

  function test_reindex_answer_unblocks() {
    m.reindex()
    m._reindexer.deliver(JSON.stringify({ok:true, indexStale:false, message:"index rebuilt"}))
    m._reindexer.finish(0)
    compare(m.reindexing, false)
    compare(m.indexStale, false)
    compare(m.message, "index rebuilt")
  }

  // #59: the terminal apply must not start under a running write.
  function test_terminal_apply_refused_while_busy() {
    m.busy = true
    compare(m.applyInTerminal(), false, "so the menu stays open")
    compare(m._applyTerm.running, false)
    verify(m.message.indexOf("still writing") >= 0, "it says why")
  }

  // A state answer and a rows answer are told apart by shape, not by which
  // command was run. reindex answers {ok, indexStale, message} and nothing
  // else, and absorbing that as state used to empty every tab (#26).
  function test_absorb_dispatches_by_shape() {
    m._absorb(JSON.stringify({ ok: true, apps: [{ id: "a" }], services: [] }), false)
    compare(m.state.apps.length, 1, "a state answer becomes the catalogue")

    m._absorb(JSON.stringify({ ok: true, rows: [{ name: "x" }] }), false)
    compare(m.results.length, 1, "a rows answer becomes results")
    compare(m.state.apps.length, 1, "and must NOT overwrite the catalogue")

    m._absorb(JSON.stringify({ ok: true, indexStale: false, message: "index rebuilt" }), false)
    compare(m.state.apps.length, 1, "nor may an answer carrying neither")
  }

  // #43: a mode must not outlive the tab it belongs to. Left behind, naming
  // sent every keystroke into the input name and turned RETURN into a
  // declare against a ref from the tab the user had already left.
  function test_setTab_abandons_naming() {
    m._absorb(JSON.stringify({ ok: true, apps: [], services: [] }), false)
    m.inspected = { ref: "path:/tmp/x", ok: true, nixosModules: ["default"] }
    var suggested = m.beginNaming()
    verify(suggested !== null, "naming must start from an inspection")
    compare(m.naming, true)

    var abandoned = 0
    function onAbandoned() { abandoned++ }
    m.namingAbandoned.connect(onAbandoned)
    m.setTab(1)
    m.namingAbandoned.disconnect(onAbandoned)

    compare(m.naming, false, "changing tab must cancel naming")
    compare(abandoned, 1, "and must say it was abandoned, not cancelled by ESC")
  }

  // The same signal must NOT fire for the ESC path: Menu.qml puts the
  // flakeref back in the field there, on purpose (#43).
  function test_cancelNaming_is_not_an_abandonment() {
    m.inspected = { ref: "path:/tmp/y", ok: true, nixosModules: ["default"] }
    m.beginNaming()
    compare(m.naming, true)

    var abandoned = 0
    function onAbandoned() { abandoned++ }
    m.namingAbandoned.connect(onAbandoned)
    m.cancelNaming()
    m.namingAbandoned.disconnect(onAbandoned)

    compare(m.naming, false)
    compare(abandoned, 0, "ESC cancels without abandoning -- the field keeps the ref")
  }

  // #43: search and state shared one Process, and assigning .command while
  // it was already running is a no-op -- so a reindex or an apply finishing
  // during a search silently dropped its state read.
  function test_search_and_state_are_separate_processes() {
    verify(m._reader !== m._searcher, "they must not be the same object")
    m.refresh()
    compare(m._reader.running, true, "refresh occupies the reader")
    m.setTab(2)
    m.setQuery("git")
    m.runSearch()
    compare(m._searcher.running, true, "and a search still starts on its own channel")
    compare(m._reader.running, true, "without disturbing the read in flight")
  }

  // #43: busy is cleared by the answer and by nothing else, so a writer
  // that died without one left the panel refusing every later write with
  // "still writing". This is what keeps the writingPath interlock true in
  // the failure case.
  function test_writer_that_dies_unblocks_the_panel() {
    m.busy = true
    m._writer.finish(127)
    compare(m.busy, false, "a writer that exits without answering must unblock")
  }

  // And the ordinary path still clears it.
  function test_writer_that_answers_unblocks_the_panel() {
    m.busy = true
    m._writer.deliver(JSON.stringify({ ok: true, apps: [], services: [] }))
    compare(m.busy, false)
  }

  // ---- #60: the queue is what apply will copy ----------------------

  function test_queue_unknown_before_any_answer() { compare(m.queued, -1) }

  function test_error_answer_is_unknown() {
    m._pending.deliver(JSON.stringify({ ok: false, error: "boom" }))
    compare(m.queued, -1)
    compare(m.queueError, "boom")
  }

  function test_zero_total_stays_zero() {
    m._pending.deliver(pend({ total: 0 }))
    compare(m.queued, 0)
  }

  function test_arming_reads_afresh_then_confirms() {
    compare(m.armApply("here"), false)
    compare(m.armingState, "reading")
    m._pending.deliver(pend({}))
    compare(m.armingState, "armed")
    compare(m.armedApply, "here")
    compare(m.armedPins.apps, "aa")
    verify(m.message.indexOf("1 change") >= 0, m.message)
    compare(m.armApply("here"), true)
    compare(m.armedPins.apps, "aa", "pins survive the confirming press")
  }

  function test_old_run_does_not_arm() {
    m.refreshPending()
    compare(m._pending.running, true)
    m.armApply("here")
    m._pending.deliver(pend({}))
    compare(m.armingState, "reading", "an answer from before the press must not arm")
    m._pending.finish(0)
    m._pending.deliver(pend({}))
    compare(m.armingState, "armed")
  }

  function test_changed_queue_disarms() {
    m.armApply("here")
    m._pending.deliver(pend({}))
    m._pending.deliver(pend({ fingerprint: "f2" }))
    compare(m.armingState, "")
    verify(m.message.indexOf("the queue changed") >= 0)
  }

  function test_arming_reads_afresh_when_queue_unknown() {
    var bad = JSON.stringify({ ok: false, error: "an earlier write was interrupted (x)" })
    m._pending.deliver(bad)
    compare(m.armApply("here"), false)
    compare(m.armingState, "reading")
    m._pending.deliver(bad)
    compare(m.armingState, "")
    compare(m.message, "an earlier write was interrupted (x)")
  }

  function test_armed_then_interrupted_says_why() {
    m.armApply("here")
    m._pending.deliver(pend({}))
    compare(m.armingState, "armed")
    m._pending.deliver(JSON.stringify({ ok: false, error: "an earlier write was interrupted (x)" }))
    compare(m.armingState, "")
    compare(m.message, "an earlier write was interrupted (x)")
  }

  function test_armed_then_writing_disarms() {
    m.armApply("here")
    m._pending.deliver(pend({}))
    compare(m.armingState, "armed")
    m._pending.deliver(pend({ writing: true }))
    compare(m.armingState, "")
    compare(m.message, "a write is in progress -- try again in a moment")
  }

  function test_queue_error_is_one_note_row() {
    m._pending.deliver(pend({ changes: [{ kind: "app", id: "x", path: "a", detail: "d" }] }))
    m.checkResult = { verdict: "evaluates", fingerprint: "f1" }
    m._pending.deliver(JSON.stringify({ ok: false, error: "an earlier write was interrupted (x)" }))
    var r = m.queueRows()
    compare(r.length, 1)
    compare(r[0].kind, "note")
    compare(r[0].text, "an earlier write was interrupted (x)")
  }

  function test_apply_sends_the_frozen_pins() {
    m.armApply("here")
    m._pending.deliver(pend({ pins: { apps: "abc" } }))
    compare(m.armApply("here"), true)
    m.apply()
    compare(m._apply.command.join(" "), m.script + " apply --pin apps=abc")
    compare(m.armedKind, "")
    compare(Object.keys(m.armedPins).length, 0)
  }

  function test_draft_only_change_clears_check() {
    m._pending.deliver(pend({}))
    m.checkResult = { verdict: "evaluates", fingerprint: "f1" }
    m._pending.deliver(pend({ fingerprint: "f2" }))
    compare(m.checkResult, null)
  }

  function test_stale_check_is_superseded() {
    m._pending.deliver(pend({}))
    m.checkRunning = true
    m._check.deliver(JSON.stringify({ ok: true, verdict: "evaluates", fingerprint: "old" }))
    compare(m.checkResult.verdict, "superseded")
  }

  function test_cancelled_check_drops_its_result() {
    m.check(false)
    m.cancelCheck()
    m._check.deliver(JSON.stringify({ ok: true, verdict: "evaluates", fingerprint: "f1" }))
    m._check.finish(0)
    compare(m.checkResult, null)
    compare(m.checkRunning, false)
  }

  // The real Process may report the exit before stdout is read.
  function test_cancelled_check_drops_a_late_result() {
    m.check(false)
    m.cancelCheck()
    m._check.finish(0)
    m._check.deliver(JSON.stringify({ ok: true, verdict: "evaluates", fingerprint: "f1" }))
    compare(m.checkResult, null)
  }

  function test_check_result_after_exit_still_counts() {
    m.check(false)
    m._check.finish(0)
    m._check.deliver(JSON.stringify({ ok: true, verdict: "evaluates", fingerprint: "" }))
    compare(m.checkResult.verdict, "evaluates")
    compare(m.queueRows()[0].verdict, "evaluates")
  }

  // Only a verdict about a known selection can be out of date.
  function test_unknown_check_is_not_superseded() {
    m._pending.deliver(pend({}))
    m.check(false)
    m._check.deliver(JSON.stringify({ ok: true, verdict: "unknown", reason: "r", fingerprint: "old" }))
    compare(m.checkResult.verdict, "unknown")
    m.cancelCheck(); m._check.finish(0)
    m.check(false)
    m._check.deliver(JSON.stringify({ ok: true, verdict: "evaluates", fingerprint: "" }))
    compare(m.checkResult.verdict, "evaluates")
  }

  // Exit before stdout: the rerun must wait for the answer, or the old
  // answer would be counted as the fresh read.
  function test_exit_before_answer_does_not_arm_on_the_old_read() {
    m.refreshPending()
    m.armApply("here")
    m._pending.finish(0)
    compare(m.armingState, "reading")
    m._pending.deliver(pend({}))
    compare(m.armingState, "reading", "the old read must not arm")
    compare(m._pendingRun, m._armWant, "and the fresh read has started")
    m._pending.deliver(pend({}))
    compare(m.armingState, "armed")
  }

  function test_row_texts() {
    m._pending.deliver(pend({
      total: 5,
      writing: true,
      sources: { apps: "/c/apps.nix" },
      changes: [
        { marker: "app:foo", file: "apps", line: "x", change: "on", lineNo: 3 },
        { marker: "app:bar", file: "apps", line: "y", change: "off", lineNo: null },
        { marker: "service:baz", file: "services", line: "z", change: "modified", lineNo: null } ],
      files: [
        { file: "packages/foo.nix", label: "packages/foo.nix", status: "new", unmarked: 0,
          hunk: "h", conflict: "blocks", explained: false, path: "/c/packages/foo.nix" },
        { file: "advanced", label: "advanced.nix", status: "modified", unmarked: 2,
          hunk: "", conflict: "overwrite", explained: false, path: "/c/advanced.nix" } ],
      unpinned: { drafts: ["packages/foo.nix"] } }))
    var t = m.queueRows().map(function (r) { return r.text })
    verify(t.indexOf("foo on (apps.nix:3)") >= 0, t.join("|"))
    verify(t.indexOf("bar off (apps.nix)") >= 0, t.join("|"))
    verify(t.indexOf("baz changed (services.nix)") >= 0, t.join("|"))
    verify(t.indexOf("packages/foo.nix: new") >= 0, t.join("|"))
    verify(t.indexOf("advanced.nix: 2 lines changed") >= 0, t.join("|"))
    verify(t.indexOf("packages/foo.nix was edited in the flake -- apply will stop") >= 0, t.join("|"))
    verify(t.indexOf("advanced.nix was edited in the flake -- apply will keep a copy and overwrite it") >= 0, t.join("|"))
    verify(t.indexOf("a write is in progress or was interrupted -- the queue may be out of date") >= 0)
    verify(t.indexOf("not pinned: the flake's own files, and drafts: packages/foo.nix") >= 0, t.join("|"))
    compare(m.queueRows()[t.indexOf("foo on (apps.nix:3)")].path, "/c/apps.nix")
    m.checkResult = { verdict: "fails", summary: "bad", at: { file: "a.nix", line: 4 } }
    compare(m.queueRows()[0].text, "fails: bad (a.nix:4, as checked)")
  }

  function test_tab_counts() {
    m.state = { packages: [{}, {}] }
    compare(m.tabCount(2), "2")
    m.setTab(2); m.query = "x"
    m.results = [{}, {}, {}, {}, {}]
    compare(m.tabCount(2), "2", "a search does not change the selection's count")
    m.query = ""
    m.state = { packages: [] }
    compare(m.tabCount(2), "0")
    m.state = {}
    compare(m.tabCount(2), "")
    m.queued = 3
    compare(m.tabCount(6), "3")
    m.queued = 0
    compare(m.tabCount(6), "")
    m.queued = -1; m.queueError = ""
    compare(m.tabCount(6), "")
    m.queueError = "boom"
    compare(m.tabCount(6), "?")
    compare(m.tabCount(0), "")
    compare(m.tabCount(4), "")
    m.results = []
  }

  function test_catalogue_search_all_words_and_blank_query() {
    var rows = [{ id: "alpha", label: "Beta", category: "tools" },
                { id: "alpha", label: "Gamma", category: "tools" }]
    m.query = "b a"
    compare(m.filtered(rows).length, 1)
    compare(m.filtered(rows)[0].label, "Beta")
    m.query = "   "
    compare(m.searching, false)
    compare(m.filtered(rows).length, 2)
  }

  // #75: whatever shrank the rows, the cursor must still name a row.
  function test_cancel_check_clamps_cursor() {
    m.setTab(6)
    m._pending.deliver(pend({ changes: [ { marker: "app:a", change: "on", file: "apps", line: "x" },
                                         { marker: "app:b", change: "on", file: "apps", line: "y" } ] }))
    m.checkResult = null
    m.checkRunning = true
    m.cursor = m.count - 1
    m.cancelCheck()
    m._check.finish(143)
    verify(m.cursor <= m.count - 1, "cursor " + m.cursor + " of " + m.count)
  }

  function test_naming_clamps_cursor() {
    m.setTab(5)
    m.inspected = { ref: "path:/tmp/z", ok: true, nixosModules: ["a", "b", "c"] }
    m.cursor = m.count - 1
    verify(m.cursor >= 2)
    m.beginNaming()
    compare(m.cursor, 0)
  }

  function test_catalogue_rows_group_and_settings_last() {
    m.state = { apps: [{ id: "a", category: "A" }, { id: "b", category: "B" },
                       { id: "c", category: "A" },
                       { id: "s.settings", category: "A", settings: true }] }
    m.setTab(0)
    compare(m.rows().map(function (r) { return r.id }).join(), "a,c,b,s.settings")
    compare(m.rows().map(function (r) { return r.section }).join("|"),
            "A|A|B|settings \u2014 edit in apps.nix")
    compare(m.rowAt(3).settings, true)
    m.cursor = 3
    m.activate()
    verify(m.message.indexOf("configures") >= 0, "it explains instead of toggling")
    compare(m.busy, false, "and starts no write")

    m.state = { apps: [{ id: "x", category: "constructor" }, { id: "y", category: "__proto__" },
                       { id: "z", category: "constructor" }] }
    compare(m.rows().map(function (r) { return r.id }).join(), "x,z,y")
    compare(m.rows().map(function (r) { return r.section }).join("|"),
            "constructor|constructor|__proto__")
  }

  // ---- #62: where the option list came from ------------------------

  function test_search_reports_the_option_source() {
    m._absorb(JSON.stringify({ ok: true, indexStale: false, query: "x", rows: [],
      options: { source: "system", stale: false } }), false)
    compare(m.optionsSource, "system")
    compare(m.optionsStatus, "options: system manual")
    m._absorb(JSON.stringify({ ok: true, indexStale: false, query: "x", rows: [],
      options: { source: "flake", stale: false } }), false)
    compare(m.optionsStatus, "", "a fresh flake read needs no footer text")
  }

  function test_state_reads_optionsInfo_not_options() {
    // `options` in a state answer is the rows set in apps.nix: an array.
    m._absorb(JSON.stringify({ ok: true, apps: [], services: [], packages: [], options: [],
      optionsInfo: { source: "flake", stale: false } }), false)
    compare(m.optionsSource, "flake")
  }

  function test_stale_cache_refreshes_once_per_session() {
    var st = JSON.stringify({ ok: true, apps: [], services: [], packages: [], options: [],
      optionsInfo: { source: "flake", stale: true } })
    m._absorb(st, false)
    compare(m.optionsStale, true)
    compare(m._optionsRefresh.command.join(" "), m.script + " options refresh")
    compare(m._optionsRefresh.running, true)
    compare(m.optionsStatus, "options: reading your flake\u2026")
    m._optionsRefresh.deliver(JSON.stringify({ ok: true, source: "flake" }))
    compare(m.optionsStale, false, "the refresh answer clears it")
    m._absorb(st, false)
    compare(m._optionsRefresh.running, false, "not again in the same session")
  }

  function test_refresh_failure_shows_its_error() {
    m.refreshOptions()
    m._optionsRefresh.deliver(JSON.stringify({ ok: false, error: "timed out after 5 minutes" }))
    compare(m.optionsError, "timed out after 5 minutes")
    compare(m.optionsStatus, "options: timed out after 5 minutes")
    m._optionsRefresh.deliver(JSON.stringify({ ok: true, source: "flake" }))
    compare(m.optionsError, "", "a later good read clears it")
  }

  function test_search_and_state_keep_refresh_error_until_success() {
    m.refreshOptions()
    m._optionsRefresh.deliver(JSON.stringify({ ok: false, error: "eval failed" }))
    m._absorb(JSON.stringify({ ok: true, query: "git", rows: [],
      options: { source: "flake", stale: false } }), false)
    m._absorb(JSON.stringify({ ok: true, apps: [], services: [], packages: [], options: [],
      optionsInfo: { source: "flake", stale: false } }), false)
    compare(m.optionsError, "eval failed")
    m._absorb(JSON.stringify({ ok: true, indexStale: false,
      options: { ok: true, source: "flake", stale: false } }), false)
    compare(m.optionsError, "", "a successful reindex refresh clears it")
  }

  function test_refresh_repeats_visible_option_search() {
    m.setTab(3)
    m.setQuery("git")
    m.runSearch()
    m._searcher.deliver(JSON.stringify({ ok: true, query: "git", rows: [{ name: "old cache" }] }))
    m.results = [{ name: "old cache" }]
    m.refreshOptions()
    m._optionsRefresh.deliver(JSON.stringify({ ok: true, source: "flake" }))
    compare(m._searcher.running, true)
    compare(m._searcher.command[m._searcher.command.length - 1], "git")
  }

  function test_refresh_queues_option_search_already_in_flight() {
    m.setTab(3)
    m.setQuery("git")
    m.runSearch()
    m.refreshOptions()
    m._optionsRefresh.deliver(JSON.stringify({ ok: true, source: "flake" }))
    compare(m._searchAgain, true)
    m._searcher.deliver(JSON.stringify({ ok: true, query: "git", rows: [{ name: "old cache" }] }))
    compare(m._searcher.running, true, "a fresh search follows the old answer")
    compare(m._searcher.command[m._searcher.command.length - 1], "git")
  }

  function test_post_apply_refreshes_rerun_after_inflight_reads() {
    m.refresh()
    m.refreshOptions()
    m._apply.stdout.feed('{"nixarchyPkgApply":{"ok":true,"message":"applied"}}')
    compare(m._readerAgain, true)
    compare(m._optionsAgain, true)
    m._reader.deliver(JSON.stringify({ ok: true, apps: [], services: [], packages: [], options: [] }))
    m._optionsRefresh.deliver(JSON.stringify({ ok: true, source: "flake" }))
    compare(m._reader.running, true, "state runs again after the first answer")
    compare(m._optionsRefresh.running, true, "options run again after the first answer")
  }

  function test_reindex_shows_options_reading_without_false_eta() {
    m.reindex()
    verify(m.optionsReading)
    compare(m.optionsStatus, "options: reading your flake\u2026")
    verify(m.message.indexOf("45 s") < 0)
    m._reindexer.finish(0)
    compare(m.optionsReading, false)
  }

  function test_reindex_answer_carries_the_options_result() {
    m._absorb(JSON.stringify({ ok: true, indexStale: false, message: "index rebuilt",
      options: { ok: false, error: "no flake at /etc/nixos" } }), false)
    compare(m.optionsError, "no flake at /etc/nixos")
  }

  function test_successful_apply_refreshes_options() {
    m._apply.stdout.feed('{"nixarchyPkgApply":{"ok":false,"message":"nope"}}')
    compare(m._optionsRefresh.running, false, "not after a failed apply")
    m._apply.stdout.feed('{"nixarchyPkgApply":{"ok":true,"message":"applied"}}')
    compare(m._optionsRefresh.running, true)
    compare(m._optionsRefresh.command.join(" "), m.script + " options refresh")
  }
}
