import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The catalogue on a keybind, over whatever you were working in.
//
// Installing something should not need the mouse, so this entry point
// holds the keyboard while it is up and everything is reachable from the
// home row. The bar widget draws the same card; only the way in differs.
Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool keysOpen: false

  // The output Hyprland has focused, which is where a keyboard-summoned
  // surface belongs. Resolved on the way in rather than bound, so the menu
  // does not move to another screen while it is being read.
  property var targetScreen: null

  readonly property int cardWidth: Style.space(900)

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === name) return screens[i]
    return null
  }

  // Plugin lifecycle. The host calls open(payloadJson) after
  // `omarchy-shell shell summon nixarchy.pkg ...` and close() when hidden.
  function open(payloadJson) {
    root.targetScreen = root.focusedScreen()
    root.opened = true
    pkg.refresh()
    Qt.callLater(function () { keys.forceActiveFocus() })
  }

  function close() {
    root.keysOpen = false
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  PkgModel {
    id: pkg
    host: root
  }

  PanelWindow {
    id: panel

    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "nixarchy-pkg-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    onVisibleChanged: if (visible) Qt.callLater(function () { keys.forceActiveFocus() })

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    // Clicking away closes, as every summoned surface on this desktop
    // does. The card declares its own MouseArea so a click inside it does
    // not reach this one.
    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: surface
      width: Math.min(root.cardWidth, Math.round(panel.width * 0.72))
      height: Math.min(Math.max(Style.space(420), card.bodyHeight + padding * 2),
                       panel.height - Style.gapsOut * 2)
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.max(Style.gapsOut, Math.round((panel.height - height) / 2))
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border,
                                     Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      FocusScope {
        id: keys
        anchors.fill: parent
        anchors.topMargin: surface.contentTopInset
        anchors.rightMargin: surface.contentRightInset
        anchors.bottomMargin: surface.contentBottomInset
        anchors.leftMargin: surface.contentLeftInset
        focus: true

        Keys.onPressed: function (event) {
          if (form.open) return            // the form owns the keyboard
          if (root.keysOpen) {
            root.keysOpen = false
            event.accepted = true
            return
          }
          if (pkg.applying || pkg.applyLog.length > 0) {
            // ESC leaves the build running: it is elevating, downloading
            // and switching a system, and killing it half way through is
            // never what reaching for ESC meant.
            if (event.key === Qt.Key_Escape) { pkg.detachFromLog(); event.accepted = true }
            return
          }

          switch (event.key) {
            case Qt.Key_Escape:
              if (search.text.length > 0) { search.text = "" ; pkg.setQuery("") }
              else root.close()
              event.accepted = true; return
            case Qt.Key_Down:  pkg.moveCursor(1);  event.accepted = true; return
            case Qt.Key_Up:    pkg.moveCursor(-1); event.accepted = true; return
            case Qt.Key_PageDown: pkg.moveCursor(10);  event.accepted = true; return
            case Qt.Key_PageUp:   pkg.moveCursor(-10); event.accepted = true; return
            case Qt.Key_Home:  pkg.cursor = 0; event.accepted = true; return
            case Qt.Key_Left:  pkg.setTab(pkg.tab - 1); event.accepted = true; return
            case Qt.Key_Right: pkg.setTab(pkg.tab + 1); event.accepted = true; return
            case Qt.Key_Tab:   pkg.setTab(pkg.tab + 1); event.accepted = true; return
            case Qt.Key_Backtab: pkg.setTab(pkg.tab - 1); event.accepted = true; return
            case Qt.Key_Return:
            case Qt.Key_Enter:
              root.activateRow(); event.accepted = true; return
            case Qt.Key_Space:
              // Space toggles only where a row has two states; in a search
              // field it is a space, so the field handles it first.
              if (!search.activeFocus) { pkg.activate(); event.accepted = true; return }
              break
          }

          // Single letters, only while the search field does not have the
          // keyboard -- otherwise "a" could not be typed into a query.
          if (!search.activeFocus && event.modifiers === Qt.NoModifier) {
            switch (event.key) {
              case Qt.Key_J: pkg.moveCursor(1);  event.accepted = true; return
              case Qt.Key_K: pkg.moveCursor(-1); event.accepted = true; return
              case Qt.Key_H: pkg.setTab(pkg.tab - 1); event.accepted = true; return
              case Qt.Key_L: pkg.setTab(pkg.tab + 1); event.accepted = true; return
              case Qt.Key_Slash: search.forceActiveFocus(); event.accepted = true; return
              case Qt.Key_Question: root.keysOpen = true; event.accepted = true; return
              case Qt.Key_A: pkg.apply(); event.accepted = true; return
              case Qt.Key_R: pkg.reindex(); event.accepted = true; return
            }
          }
        }

        // ---- search -----------------------------------------------------

        TextField {
          id: search
          anchors { top: parent.top; left: parent.left; right: parent.right }
          placeholderText: pkg.indexTab ? "search nixpkgs…" : "filter…"
          foreground: Color.menu.text
          onTextChanged: pkg.setQuery(text)
          Keys.onPressed: function (event) {
            switch (event.key) {
              case Qt.Key_Down:
              case Qt.Key_Up:
              case Qt.Key_Return:
              case Qt.Key_Enter:
              case Qt.Key_Escape:
                // Movement and commitment belong to the list, so the field
                // hands the keyboard back rather than competing for it.
                keys.forceActiveFocus()
                event.accepted = false
                return
            }
          }
        }

        Card {
          id: card
          anchors {
            top: search.bottom; topMargin: Style.space(12)
            left: parent.left; right: parent.right; bottom: parent.bottom
          }
          visible: !pkg.applying && pkg.applyLog.length === 0 && !root.keysOpen
          model: pkg
          maxHeight: surface.height - surface.padding * 2 - search.height
          onRequestEdit: function (row) { form.begin(row) }
        }

        // ---- the build log ----------------------------------------------

        Flickable {
          id: logView
          anchors {
            top: search.bottom; topMargin: Style.space(12)
            left: parent.left; right: parent.right; bottom: parent.bottom
          }
          visible: pkg.applying || pkg.applyLog.length > 0
          contentHeight: logText.implicitHeight
          clip: true
          // Follows the tail, which is the part of a build anyone watches.
          onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

          Text {
            id: logText
            width: logView.width
            // A build log is external text. Plain, always.
            text: pkg.applyLog.join("\n")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.menu.text
          }
        }

        // ---- the key sheet ----------------------------------------------

        // The menu's keys exist only while it holds the keyboard, so
        // Hyprland's keybinding list cannot show them. `?` does.
        Text {
          anchors.fill: parent
          anchors.topMargin: search.height + Style.space(12)
          visible: root.keysOpen
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.menu.text
          text: [
            "j / k   or   ↓ ↑        move",
            "h / l   or   ← →        change tab",
            "TAB                     next tab",
            "/                       search",
            "SPACE                   turn the row on or off",
            "RETURN                  edit an option, or add a search result",
            "a                       apply the queued changes",
            "R                       rebuild the search index",
            "?                       this sheet",
            "ESC                     clear the search, then close"
          ].join("\n")
        }

        // ---- the option form --------------------------------------------

        OptionForm {
          id: form
          anchors.fill: parent
          model: pkg
          onClosed: Qt.callLater(function () { keys.forceActiveFocus() })
        }
      }
    }
  }

  // RETURN means "tell me more and let me set it" on an option, and "add
  // it" on a search result. On a plain catalogue row there is nothing more
  // to say, so it does what SPACE does.
  function activateRow() {
    var row = pkg.rowAt(pkg.cursor)
    if (!row) return
    if (pkg.tab === 3) {
      form.begin(row)
      return
    }
    pkg.activate()
  }
}
