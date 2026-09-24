// The shell's Style, reduced to the members this plugin actually binds.
//
// These values are asserted NOWHERE. The stub exists so our code can run,
// not to pin down what the shell returns -- an assertion that failed
// because omarchy changed would be a false alarm, and the spec says to
// delete such a test rather than keep it (#50).
pragma Singleton
import QtQuick

QtObject {
  function space(v) { return Math.max(1, Math.round(v)) }
  readonly property real cornerRadius: 0
  readonly property real gapsOut: 10
  readonly property var font: ({ family: "monospace", heading: 16, title: 14 })
  readonly property var bar: ({ iconFont: 16 })
  readonly property var spacing: ({ panelPadding: 10, dropdownWidth: 200 })
}
