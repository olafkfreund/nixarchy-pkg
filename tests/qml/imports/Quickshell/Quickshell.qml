// As Quickshell's singleton, reduced to what Card binds. Every icon is
// missing here, which is the case Card must draw as nothing.
pragma Singleton
import QtQuick

QtObject {
  function iconPath(icon, check) { return "" }
}
