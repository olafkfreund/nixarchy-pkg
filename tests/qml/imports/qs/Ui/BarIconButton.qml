// Shape of the host's BarIconButton: what Panel binds, and the press signal.
// iconComponent is never instantiated, so the drawing is not under test.
import QtQuick
// Panel-facing properties and press signal only; iconComponent is not drawn.

Item {
  property var bar: null
  property string text: ""
  property string tooltipText: ""
  property color foreground: "white"
  property Component iconComponent: null
  signal pressed(int buttonCode)
  implicitWidth: 24
  implicitHeight: 24
}
