// Only the existence of these border specs matters here (#50).
pragma Singleton
import QtQuick

QtObject {
  function surfaceSpec(a, b, c, d) { return ({}) }
  function controlSpec(a, b, c) { return ({}) }
}
