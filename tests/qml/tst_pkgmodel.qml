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
    if (m.naming) m.cancelNaming()
    m.setTab(0)
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
}
