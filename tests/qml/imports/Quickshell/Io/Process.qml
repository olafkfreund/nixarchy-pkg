// A Process that runs nothing.
//
// Shape, never behaviour: this carries exactly what PkgModel binds, and
// models no semantics at all. Nothing is spawned, nothing is buffered,
// nothing is parsed. Where a test needs something to have happened, the
// test makes it happen -- `deliver()` for an answer, `finish()` for a
// death (#50).
//
// `exited` matters more than it looks: #43's onExited fix is what keeps the
// `busy` interlock true when a writer dies without answering, and a stub
// that could not emit this would quietly leave that fix unprotected.
import QtQuick

QtObject {
  property var command: []
  property bool running: false
  property var stdout: null

  signal exited(int code, int status)

  // Pretend the adapter answered. The collector is whatever the subject
  // attached, so this drives the real handler the subject wrote.
  function deliver(text) {
    if (stdout && stdout.feed) stdout.feed(text)
    running = false
  }

  // Pretend the process ended without answering.
  function finish(code) {
    running = false
    exited(code, 0)
  }
}
