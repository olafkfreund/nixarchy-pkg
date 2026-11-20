pragma Singleton
import QtQuick
// Screens and icon-path shape only; no host shell runs.
QtObject {
  property var screens: []
  property var launched: []
  function execDetached(cmd) { launched.push(cmd) }
  function iconPath(icon, check) { return icon === "two" ? "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" : "" }
}
