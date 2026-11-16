// Shape of the host's BarWidget: the two properties Panel sets or reads.
import QtQuick
// Panel-facing moduleName and bar only; no host bar runs.

Item {
  property string moduleName: ""
  property var bar: null
}
