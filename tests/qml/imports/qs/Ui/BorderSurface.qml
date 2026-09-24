// Card binds no qs.Ui type, but a qmldir declaring a module with NO types
// makes Qt report `module "qs.Ui" is not installed` -- which reads like a
// missing import path and is not. One type is the cost of the import
// resolving at all (#50).
import QtQuick

Rectangle {
  property var borderSpec
  property real padding: 0
  default property alias content: inner.data
  Item { id: inner; anchors.fill: parent }
}
