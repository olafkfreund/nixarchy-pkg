import QtQuick
import Quickshell
import Quickshell.Io
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
  property string keyText: ""

  // The output Hyprland has focused, which is where a keyboard-summoned
  // surface belongs. Resolved on the way in rather than bound, so the menu
  // does not move to another screen while it is being read.
  property var targetScreen: null

  readonly property int cardWidth: Style.space(1100)

  // One scale for the whole surface, passed to the card so the search
  // line, the list and the log all grow together. A catalogue read at
  // full screen is read like a document, not like a bar widget.
  readonly property real textScale: 1.45
  function px(base) { return Math.round(base * root.textScale) }

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
  // Summoned fresh every time. The plugin is keepLoaded, so without this
  // the menu comes back holding the last search, on the last tab, with the
  // keyboard still in the search box -- and the first `l` meant to change
  // tab types an l into a stale query instead.
  function open(payloadJson) {
    root.targetScreen = root.focusedScreen()
    root.keysOpen = false
    search.text = ""
    pkg.setQuery("")
    pkg.setTab(0)
    pkg.message = ""
    root.opened = true
    pkg.refresh()
    Qt.callLater(root.focusList)
  }

  // Give the list the keyboard. forceActiveFocus() on a FocusScope hands
  // the keyboard to whichever child held it last, so asking the scope alone
  // gives it straight back to the search box -- or to the option form,
  // hidden but still focused -- and the next `l` meant to change tab is
  // typed into the query. Every child that can hold focus lets go first.
  // Every site that means "the list has it now" comes through here (#27).
  function focusList() {
    search.focus = false
    form.focus = false
    keys.forceActiveFocus()
  }

  // j/k, the arrows, the page keys and Home/End scroll a read-only view:
  // the key sheet and the build log are both taller than the card, and a
  // keyboard-first surface cannot leave half of either behind a mouse
  // wheel (#27). Returns whether the key was one of them.
  function scrollView(view, key) {
    var line = root.px(Style.font.caption) * 1.35
    var max = Math.max(0, view.contentHeight - view.height)
    var y = view.contentY
    switch (key) {
      case Qt.Key_J: case Qt.Key_Down:     y += line; break
      case Qt.Key_K: case Qt.Key_Up:       y -= line; break
      case Qt.Key_PageDown:                y += view.height * 0.9; break
      case Qt.Key_PageUp:                  y -= view.height * 0.9; break
      case Qt.Key_Home:                    y = 0; break
      case Qt.Key_End:                     y = max; break
      default: return false
    }
    view.contentY = Math.max(0, Math.min(max, y))
    return true
  }

  // Name an input before declaring it (#29): the suggestion goes into the
  // field, selected, so RETURN takes it and typing replaces it.
  function startNaming() {
    var s = pkg.beginNaming()
    if (s === null) return
    search.text = s
    search.selectAll()
    search.forceActiveFocus()
  }

  function close() {
    root.keysOpen = false
    // The form holds the keyboard while it is up, and the key handler above
    // steps aside for it. Closing the menu from outside -- a click away, or
    // `omarchy-shell shell hide` -- left it open, so the menu came back
    // deaf to every key with nothing on screen to explain why.
    if (form.open) form.finish()
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

    onVisibleChanged: if (visible) Qt.callLater(root.focusList)

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
      // A share of the screen rather than a measurement of the contents:
      // the list fills the card and the card cannot ask the list how tall
      // it would like to be without the two chasing each other.
      height: Math.min(Math.round(panel.height * 0.78),
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
            // The scroll keys read the sheet; anything else puts it away.
            if (!root.scrollView(keySheetView, event.key)) root.keysOpen = false
            event.accepted = true
            return
          }
          if (pkg.showingLog) {
            // ESC leaves the build running: it is elevating, downloading
            // and switching a system, and killing it half way through is
            // never what reaching for ESC meant.
            if (event.key === Qt.Key_Escape) { pkg.detachFromLog(); event.accepted = true }
            // Scrolling back stops the view chasing the tail; End resumes.
            else if (root.scrollView(logView, event.key)) {
              logView.followTail = event.key === Qt.Key_End
              event.accepted = true
            }
            return
          }

          // An armed apply is cancelled by any other key -- but not by a
          // bare modifier: SHIFT goes down before the A of a second SHIFT+A.
          if (pkg.armedApply !== "" && event.key !== Qt.Key_A
              && event.key !== Qt.Key_Shift && event.key !== Qt.Key_Control
              && event.key !== Qt.Key_Alt && event.key !== Qt.Key_Meta
              && event.key !== Qt.Key_Super_L && event.key !== Qt.Key_Super_R)
            pkg.disarm()

          // Naming an input: RETURN declares with the name in the field,
          // ESC goes back to the inspection with the flakeref restored.
          if (pkg.naming) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (pkg.declareAs(search.text)) search.text = ""
              event.accepted = true; return
            }
            if (event.key === Qt.Key_Escape) {
              search.text = pkg.cancelNaming()
              search.forceActiveFocus()
              event.accepted = true; return
            }
          }

          switch (event.key) {
            case Qt.Key_Escape:
              // One step back per press: the inspection, then the field,
              // then the menu. Clearing all three at once loses a flakeref
              // somebody typed out by hand.
              if (pkg.clearInspection()) { event.accepted = true; return }
              if (search.text.length > 0) {
                search.text = "" ; pkg.setQuery("")
                // and hand the keyboard back, or `?` and the single letters
                // stay unreachable: they are all gated on the field NOT
                // having it, and clearing the text never moved it before.
                if (!pkg.flakeTab) root.focusList()
              }
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
              // SHIFT is the variant, the way SHIFT+A is the variant of `a`
              // below. Straight to the model rather than through
              // activateRow(), which detours tab 3 into the option form --
              // a channel key hung there would inherit that detour, and
              // addFromOtherChannel refuses every tab but the search list
              // anyway. A letter could not do this job at all: the single
              // letters further down are gated on the search field NOT
              // having the keyboard, and this key is needed while it does.
              if (event.modifiers & Qt.ShiftModifier) {
                pkg.addFromOtherChannel(); event.accepted = true; return
              }
              // Tested first among the plain-RETURN cases, because on Flakes
              // the field holds a flakeref rather than a query: RETURN asks
              // what it contains before there is any row to act on. Once
              // there is one, RETURN acts on it as everywhere else.
              if (pkg.flakeTab && pkg.inspected === null && search.text.length > 0) {
                pkg.inspect(); event.accepted = true; return
              }
              root.activateRow(); event.accepted = true; return
            case Qt.Key_Space:
              // Space toggles only where a row has two states; in a search
              // field it is a space, so the field handles it first.
              if (!search.activeFocus) { pkg.activate(); event.accepted = true; return }
              break
          }

          // `?` is shift+/ on every layout, so it is handled before the
          // no-modifier block below -- inside it, the key sheet could never
          // be opened at all.
          if (!search.activeFocus && event.key === Qt.Key_A
              && (event.modifiers & Qt.ShiftModifier)) {
            if (!event.isAutoRepeat && pkg.armApply("terminal")) {
              pkg.applyInTerminal(); root.close()
            }
            event.accepted = true; return
          }

          // r reindexes, and so does SHIFT+R: the footer said R for long
          // enough that the capital is what hands reach for. Ctrl and Alt
          // are left alone.
          if (!search.activeFocus && event.key === Qt.Key_R
              && (event.modifiers === Qt.NoModifier
                  || event.modifiers === Qt.ShiftModifier)) {
            pkg.reindex(); event.accepted = true; return
          }

          if (!search.activeFocus && event.key === Qt.Key_Question) {
            if (root.keyText.length === 0) keySheet.running = true
            keySheetView.contentY = 0
            root.keysOpen = true
            event.accepted = true
            return
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
              // Shift+A is handled above: this block only ever sees a key
              // pressed with no modifiers at all.
              case Qt.Key_A:
                if (!event.isAutoRepeat && pkg.armApply("here")) {
                  logView.followTail = true
                  pkg.apply()
                }
                event.accepted = true; return
            }
          }
        }

        // Which surface owns the keyboard is a property of the tab. Every
        // other tab is a list you move through, so the list holds it and
        // `/` asks for it. Flakes is a thing you type a reference into, and
        // a flakeref contains `/` -- so arriving without the field focused
        // means the first characters are read as tab-switching keys and the
        // slash inside the reference is what finally focuses the field.
        Connections {
          target: pkg
          function onTabChanged() {
            if (pkg.flakeTab) search.forceActiveFocus()
            else root.focusList()
          }
        }

        // ---- search -----------------------------------------------------

        TextField {
          id: search
          anchors { top: parent.top; left: parent.left; right: parent.right }
          placeholderText: pkg.naming ? "input name"
                         : pkg.flakeTab ? "github:owner/repo\u2026"
                         : pkg.tab === 3 ? "search NixOS options\u2026"
                         : pkg.indexTab ? "search nixpkgs\u2026" : "filter\u2026"
          foreground: Color.menu.text
          onTextChanged: pkg.setQuery(text)
          Keys.onPressed: function (event) {
            switch (event.key) {
              case Qt.Key_Down:
              case Qt.Key_Up:
              case Qt.Key_Tab:
              case Qt.Key_Backtab:
              case Qt.Key_Return:
              case Qt.Key_Enter:
              case Qt.Key_Escape:
                // Movement and commitment belong to the list, so the field
                // hands the keyboard back rather than competing for it.
                //
                // Moving between TABS is movement too, and that was missed:
                // without Tab and Backtab here there was no way to leave a
                // tab once anything had been typed, because the arrows and
                // the single letters are all unavailable while the field
                // holds the keyboard -- correctly, since `h` and `l` are
                // letters somebody is entitled to type.
                //
                // Tab and Backtab only. Left and Right move a caret, and the
                // field that most needs caret movement is the one holding a
                // flakeref; a rule that changed tabs only at the end of the
                // text would work and would have to be reconstructed from
                // first principles by whoever met it next.
                root.focusList()
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
          visible: !pkg.showingLog && !root.keysOpen
          model: pkg
          textScale: root.textScale
          maxHeight: surface.height - surface.padding * 2 - search.height
          onRequestActivate: root.activateRow()
        }

        // ---- the build log ----------------------------------------------

        Flickable {
          id: logView
          anchors {
            top: search.bottom; topMargin: Style.space(12)
            left: parent.left; right: parent.right; bottom: parent.bottom
          }
          visible: pkg.showingLog
          contentHeight: logText.implicitHeight
          clip: true
          // Follows the tail, which is the part of a build anyone watches --
          // until someone scrolls back to read something, and then it stays
          // where they put it. End, or the next apply, follows again.
          property bool followTail: true
          onContentHeightChanged: if (followTail) contentY = Math.max(0, contentHeight - height)

          Text {
            id: logText
            width: logView.width
            // A build log is external text. Plain, always.
            text: pkg.applyLog.join("\n")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.family: Style.font.family
            font.pixelSize: root.px(Style.font.caption)
            color: Color.menu.text
          }
        }

        // ---- the key sheet ----------------------------------------------

        // The menu's keys exist only while it holds the keyboard, so
        // Hyprland's keybinding list cannot show them. `?` does.
        //
        // Read from bin/nixarchy-pkg-keys rather than written out again
        // here: that script is also what the Learn menu shows, and a
        // second copy of the same list is a copy that goes out of date.
        Process {
          id: keySheet
          command: [pkg.script.replace(/nixarchy-pkg$/, "nixarchy-pkg-keys"), "--print"]
          stdout: StdioCollector {
            onStreamFinished: root.keyText = text
          }
        }

        Flickable {
          id: keySheetView
          anchors.fill: parent
          anchors.topMargin: search.height + Style.space(12)
          visible: root.keysOpen
          contentHeight: keyLabel.implicitHeight
          clip: true

          Text {
            id: keyLabel
            width: parent.width
            text: root.keyText
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.family: Style.font.family
            font.pixelSize: root.px(Style.font.caption)
            lineHeight: 1.35
            color: Color.menu.text
          }
        }

        // ---- the option form --------------------------------------------

        OptionForm {
          id: form
          anchors.fill: parent
          model: pkg
          textScale: root.textScale
          onClosed: Qt.callLater(root.focusList)
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
