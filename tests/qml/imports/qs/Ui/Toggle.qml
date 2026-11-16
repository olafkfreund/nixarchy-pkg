// Shape of qs.Ui's Toggle: what OptionForm binds, nothing more.
import QtQuick

Item {
  property string label: ""
  property bool checked: false
  signal clicked()
  implicitHeight: 20
}
