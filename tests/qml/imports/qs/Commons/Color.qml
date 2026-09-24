// As Style.qml: shape only, values asserted nowhere (#50).
pragma Singleton
import QtQuick

QtObject {
  readonly property color accent: "#33aaaa"
  readonly property color urgent: "#aa3333"
  readonly property color foreground: "#cccccc"
  readonly property color background: "#111111"
  readonly property var bar: ({ background: "#111111" })
  readonly property var menu: ({
    background: "#111111", border: "#444444", scrim: "#000000",
    text: "#cccccc", selectedText: "#ffffff", selectedBackground: "#222222"
  })
}
