import QtQuick
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

  // nf-linux-nixos. NOT U+2744 SNOWFLAKE, which looks like the obvious
  // choice and is in no Nerd Font on this system -- it renders as a tofu
  // box in the bar, which is how this widget spent its first outing
  // looking as though it had not loaded at all. nixi-button hand-draws its
  // snowflake for the same reason.
  readonly property string icon: "\uf313"

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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.queued > 0 ? root.icon + " " + root.queued : root.icon
    // The bar's urgent colour is for something that needs doing. A queued
    // change does: nothing is built until it is applied.
    active: root.queued > 0
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) {
        summonProc.running = true
      } else if (buttonCode === Qt.MiddleButton) {
        root.refresh()
      }
    }
  }

  PanelToolTip {
    text: root.queued === 0
      ? "nixarchy \u00b7 nothing queued"
      : root.queued + (root.queued === 1 ? " change" : " changes")
        + " waiting for a rebuild"
        + (root.neverApplied ? "\nthis machine has never run nixarchy-apply" : "")
  }
}
