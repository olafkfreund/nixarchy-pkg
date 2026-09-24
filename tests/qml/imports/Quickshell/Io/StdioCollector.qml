// Collects nothing. `feed` is the test's way in; onStreamFinished is the
// subject's way out (#50).
import QtQuick

QtObject {
  property string text: ""
  signal streamFinished()
  function feed(s) { text = s; streamFinished() }
}
