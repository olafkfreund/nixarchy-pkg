// A PanelWindow as plain items: no window, no layer shell. Its children sit
// in contentItem, which the test places in its own window.
import QtQuick
// Content shape only; no window or layer shell is created.
QtObject {
  id: win
  component Edges: QtObject { property bool top; property bool bottom; property bool left; property bool right }
  default property alias data: content.data
  property var screen: null
  property var exclusionMode: 0
  property color color: "transparent"
  property bool visible: false
  property Edges anchors: Edges {}
  readonly property real width: content.width
  readonly property real height: content.height
  readonly property Item contentItem: Item { id: content; visible: win.visible }
}
