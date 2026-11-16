// Shape of qs.Ui's Dropdown: what OptionForm binds, nothing more.
import QtQuick

Item {
  property string label: ""
  property string value: ""
  property var options: []
  signal changed(string value)
  implicitHeight: 20
}
