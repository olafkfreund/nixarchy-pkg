// Shape of qs.Ui's NumberField: what OptionForm binds, nothing more.
import QtQuick

Item {
  property string label: ""
  property int value: 0
  property int from: 0
  property int to: 100
  signal modified(int value)
  implicitHeight: 20
}
