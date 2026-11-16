// Only the specs' existence matters here (#50).
pragma Singleton
import QtQuick
// Only spec shapes are supplied; no border is drawn.

QtObject {
  function surfaceSpec(a, b, c, d) { return ({}) }
  function controlSpec(a, b, c) { return ({}) }
}
