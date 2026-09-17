import QtQuick
import QtQuick.Effects
// Screen, for devicePixelRatio. Quickshell's QML environment happens to
// provide it without this import -- herdr relies on that and works -- but
// relying on a host's import environment is relying on something nobody
// promised, and the import costs nothing.
import QtQuick.Window
import Quickshell.Io
import qs.Commons
import qs.Ui

// What is waiting for the next rebuild, in the bar.
//
// A queued change is invisible: the file is edited, nothing is built, and
// on this desktop nothing said so until the next time you happened to run
// nixarchy-apply. This widget is that reminder, and a way back into the
// list that made it.
//
// It deliberately does not redraw the whole card as a dropdown. The menu
// entry point already owns that surface and its keys, and a second copy in
// the bar would be a second interaction model to keep in step with the
// first. Clicking here summons the menu instead -- one list, two ways in.
//
// Glyphs are \u escapes rather than literal characters, so the source
// survives editors and patches that mangle private-use codepoints.
BarWidget {
  id: root

  moduleName: "nixarchy.pkg"

  property int queued: 0
  property bool neverApplied: false

  // A drawn mark rather than a font glyph. The snowflake this started with
  // was U+2744, which is in no Nerd Font here and rendered as a tofu box;
  // the NixOS glyph that replaced it is already this desktop's mark for
  // nixi. assets/package.svg is a parcel, which is what this plugin is
  // about, and belongs to nothing else.

  // The adapter, next to this file, so nothing needs to be on $PATH.
  readonly property string script:
    Qt.resolvedUrl("bin/nixarchy-pkg").toString().replace(/^file:\/\//, "")

  Process {
    id: pendingProc
    command: [root.script, "pending"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data.ok) {
            root.queued = data.count || 0
            root.neverApplied = data.neverApplied === true
          }
        } catch (e) {
          // A count nobody can read is a count not worth showing.
          root.queued = 0
        }
      }
    }
  }

  Process {
    id: summonProc
    command: ["omarchy-shell", "shell", "toggle", "nixarchy.pkg", "{}"]
  }

  function refresh() { pendingProc.running = true }

  // Cheap -- a diff of two small files -- but not free, and a queued change
  // only appears when someone edits the selection. Once a minute is often
  // enough to notice, and rarely enough to forget about.
  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // BarWidget is a bare Item and sizes itself from nothing, so a widget that
  // does not publish an implicit size is 0x0 and draws nothing at all --
  // which is exactly what this did. Every first-party widget lifts its size
  // off its button; this one now does too.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The count rides the mark as a badge, so the button itself carries no
    // text: a glyph and a number side by side would be two widgets wide.
    text: ""
    tooltipText: root.queued === 0
      ? "nixarchy \u00b7 nothing queued"
      : root.queued + (root.queued === 1 ? " change" : " changes")
        + " waiting for a rebuild"
        + (root.neverApplied ? "\nthis machine has never run nixarchy-apply" : "")

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) summonProc.running = true
      else if (buttonCode === Qt.MiddleButton) root.refresh()
    }

    iconComponent: Component {
      Item {
        Image {
          id: mark
          anchors.centerIn: parent
          width: Style.bar.iconFont
          height: Style.bar.iconFont
          source: Qt.resolvedUrl("assets/package.svg")
          // Rasterised at device pixels, or the mark is a blurred smear on
          // any display that is not 1x.
          sourceSize.width: Math.round(width * Screen.devicePixelRatio)
          sourceSize.height: Math.round(height * Screen.devicePixelRatio)
          fillMode: Image.PreserveAspectFit
          // Hidden and layered because MultiEffect draws it, not the Image.
          visible: false
          layer.enabled: true
        }

        // barForeground, not Color.foreground: on a transparent bar the
        // shell picks the icon colour off whatever is behind it, so using
        // the theme's foreground leaves the mark invisible over a light
        // wallpaper. Every other bar icon follows the same rule.
        MultiEffect {
          anchors.fill: mark
          source: mark
          colorization: 1.0
          colorizationColor: button.foreground
        }

        // The queued count rides the mark's bottom-right corner, the way an
        // unread count rides an app icon. Sized off the icon font so a theme
        // that resizes the bar takes the badge with it.
        Rectangle {
          id: badge
          visible: root.queued > 0
          anchors.horizontalCenter: mark.horizontalCenter
          anchors.horizontalCenterOffset: Math.round(Style.bar.iconFont * 0.42)
          anchors.verticalCenter: mark.verticalCenter
          anchors.verticalCenterOffset: Math.round(Style.bar.iconFont * 0.40)
          height: Math.round(Style.bar.iconFont * 0.95)
          width: Math.max(height, count.implicitWidth + Math.round(height * 0.45))
          radius: height / 2
          color: Color.accent
          // A rim in the bar's own background, so the corner the badge
          // covers still reads as a corner rather than the two shapes
          // fusing into one.
          border.width: Math.round(Style.bar.iconFont * 0.06)
          border.color: Color.bar.background

          Text {
            id: count
            anchors.centerIn: parent
            // Centring a line box leaves the digit riding high, because it
            // reserves descender room a digit never uses.
            anchors.verticalCenterOffset: Math.round(font.pixelSize * 0.1)
            text: root.queued
            textFormat: Text.PlainText
            font.family: Style.font.family
            font.pixelSize: Math.round((badge.height - 2 * badge.border.width) * 0.88)
            font.bold: true
            renderType: Text.NativeRendering
            color: Color.background
          }
        }
      }
    }
  }

}
