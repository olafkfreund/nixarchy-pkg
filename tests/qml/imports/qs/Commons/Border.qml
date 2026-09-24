// Only surfaceSpec is bound, and only its existence matters here (#50).
pragma Singleton
import QtQuick

QtObject {
  function surfaceSpec(a, b, c, d) { return ({}) }
}
