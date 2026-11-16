// As Quickshell's singleton, reduced to what Card binds. Only "two" has an
// icon here; every other one is missing, which Card must draw as nothing.
pragma Singleton
import QtQuick

QtObject {
  function iconPath(icon, check) { return icon === "two" ? "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" : "" }
}
