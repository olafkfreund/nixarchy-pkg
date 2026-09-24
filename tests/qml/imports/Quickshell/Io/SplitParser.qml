// Splits nothing. The apply log's line reader, fed one line at a time by
// the test (#50).
import QtQuick

QtObject {
  signal read(string line)
  function feed(line) { read(line) }
}
