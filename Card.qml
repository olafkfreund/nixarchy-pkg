import QtQuick
import qs.Commons
import qs.Ui

// The list, drawn the same way whether it arrived on a chord or from the
// bar. Flat: no shadows, no gradients, no rounded cards inside rounded
// cards -- one surface, rows on it, and a cursor.
//
// Every colour is a theme token. A literal here would survive a theme
// switch and look wrong, which is the one visual bug a user cannot fix.
Item {
  id: root

  property var model: null
  property real maxHeight: 0
  // The shell's base sizes are tuned for the bar and for small panels.
  // This is a full-screen list read like a document, so it sets its own
  // scale rather than inheriting one meant for a 24px-high widget.
  property real textScale: 1.45

  readonly property color fg: Color.menu.text
  readonly property color dim: Qt.darker(fg, 1.6)
  readonly property string fontFamily: Style.font.family

  readonly property real rowHeight: Math.round(px(Style.font.body) * 2.2)
  // Deliberately NOT derived from the list's contentHeight: the surface
  // sizes itself from this, the list sizes itself from the surface, and
  // reading the content back closes the circle. Qt reported that as a
  // binding loop and drew the card at whatever height it got to first.
  readonly property real bodyHeight: header.height + footer.height + Style.space(28)

  // What RETURN does, so a click cannot mean something else. It used to
  // call model.activate() directly, which on the Options tab is `opt
  // remove` -- clicking an option deleted it instead of opening its form.
  signal requestActivate(int index)

  function px(base) { return Math.round(base * root.textScale) }

  // ---- tabs -----------------------------------------------------------

  Row {
    id: header
    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: px(Style.font.body) + Style.space(14)
    spacing: Style.space(14)

    Repeater {
      model: root.model ? root.model.tabs : []

      Item {
        id: tabItem
        required property int index
        required property string modelData
        readonly property bool current: root.model && root.model.tab === index
        width: label.implicitWidth
        height: header.height

        // Rows take a click; so do the tabs above them (#30). setTab moves
        // the keyboard the way a key would.
        MouseArea {
          anchors.fill: parent
          onClicked: if (root.model) root.model.setTab(tabItem.index)
        }

        Text {
          id: label
          anchors.verticalCenter: parent.verticalCenter
          text: parent.modelData
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: root.px(Style.font.body)
          color: parent.current ? Color.menu.selectedText : root.dim
        }

        // The current tab is named by a rule under it rather than by a
        // filled pill: a pill is a second surface, and this is one.
        Rectangle {
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
          height: Math.max(1, Style.space(2))
          visible: parent.current
          color: Color.menu.selectedText
        }
      }
    }
  }

  // What this tab lists, said where it cannot be missed. The empty state
  // below cannot carry it: it draws only at zero rows, and the misreading
  // this answers happens at a SHORT list -- a selection of one, on a
  // machine whose own configuration declares hundreds, reads as a failed
  // scan rather than as a selection. So it is drawn at any row count.
  //
  // "selection" is the writers' own word, not a new one: nixarchy-pkg-remove
  // says "removed from your selection" and counts what is "still selected".
  Text {
    id: scope
    anchors { top: header.bottom; left: parent.left; right: parent.right }
    visible: root.model && root.model.tab === 2 && !root.model.searching
    height: visible ? implicitHeight + Style.space(6) : 0
    text: "packages nixarchy manages \u2014 not everything installed"
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    font.family: root.fontFamily
    font.pixelSize: root.px(Style.font.caption)
    color: root.dim
  }

  // ---- the list -------------------------------------------------------

  ListView {
    id: list
    anchors {
      top: scope.bottom; topMargin: Style.space(10)
      left: parent.left; right: parent.right; bottom: footer.top
      bottomMargin: Style.space(8)
    }
    clip: true
    model: root.model ? root.model.rows() : []
    currentIndex: root.model ? root.model.cursor : 0
    highlightMoveDuration: 0
    // Enough of the list stays on screen either side of the cursor that
    // arrowing down does not feel like it is dragging the view.
    preferredHighlightBegin: height * 0.25
    preferredHighlightEnd: height * 0.75
    highlightRangeMode: ListView.ApplyRange


    delegate: Rectangle {
      required property int index
      required property var modelData
      readonly property bool current: index === list.currentIndex

      width: list.width
      height: root.rowHeight
      color: current ? Color.menu.selectedBackground : "transparent"

      MouseArea {
        anchors.fill: parent
        onClicked: {
          if (!root.model) return
          root.model.cursor = index
          root.requestActivate(index)
        }
      }

      Row {
        anchors {
          left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
          leftMargin: Style.space(10); rightMargin: Style.space(10)
        }
        spacing: Style.space(10)

        // On, off, or nothing at all: a package or a draft is not a thing
        // with two states, so it gets no box pretending otherwise.
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: root.px(Style.font.body)
          // A .settings row is the attrset that configures an app, not a
          // thing with two states, so it must not draw a box implying one.
          // Glyphs as \u escapes, so the source survives an editor or a
          // patch that mangles them.
          text: modelData.settings === true      ? "\u2261"
              : modelData.enabled === undefined  ? "\u00b7"
              : modelData.enabled                ? "\u25a0" : "\u25a1"
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: root.px(Style.font.body)
          color: modelData.enabled ? Color.menu.selectedText : root.dim
        }

        Text {
          id: name
          anchors.verticalCenter: parent.verticalCenter
          // 42% is the name column, sized so a description can sit beside
          // it. A flake row has no second column -- it is one sentence,
          // and half of "homeManagerModules -- exists, contents cannot be
          // read" is a different and misleading statement -- so it takes
          // the width it needs.
          width: modelData.kind !== undefined
                 ? Math.min(implicitWidth, parent.width)
                 : Math.min(implicitWidth, parent.width * 0.42)
          elide: Text.ElideRight
          text: modelData.label || modelData.name || modelData.attr
                || modelData.path || modelData.id || ""
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: root.px(Style.font.body)
          color: current ? Color.menu.selectedText : root.fg
        }

        // unfree, broken, and the curated cross-reference: picking the raw
        // package gets a bare binary where the app row gets the module.
        // Worth saying before it is queued, not after it is built.
        Repeater {
          model: modelData.flags || []
          Text {
            required property string modelData
            anchors.verticalCenter: parent.verticalCenter
            text: modelData
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: root.px(Style.font.caption)
            color: modelData === "broken" ? Color.urgent
                 : modelData === "unfree" ? Color.accent
                 : root.dim
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - name.width - root.px(Style.font.body) - Style.space(40)
          elide: Text.ElideRight
          text: modelData.summary || modelData.note || modelData.type
                || modelData.line || modelData.category || ""
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: root.px(Style.font.caption)
          color: root.dim
        }
      }
    }

    // An empty list is a question, not a blank. It says which one.
    Text {
      anchors.centerIn: parent
      visible: list.count === 0
      width: parent.width - Style.space(40)
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: !root.model ? ""
          // Ahead of the searching branch: on Flakes the field holds a
          // flakeref rather than a query, so "nothing matches" is answering
          // a question nobody asked. Same shadowing trap as the indexTab
          // branch below.
          : root.model.flakeTab && root.model.inspecting
              ? "looking at \u201c" + root.model.query + "\u201d\u2026"
          : root.model.flakeTab ? (root.model.query.length > 0
              ? "RETURN to see what \u201c" + root.model.query + "\u201d offers"
              : "no flake inputs declared here yet")
          : root.model.searching ? "nothing matches \u201c" + root.model.query + "\u201d"
          // Ahead of the indexTab branch deliberately: the Selection tab is
          // also an index tab, so the general answer would shadow this one
          // and the tab that needs saying most would be the one not saying
          // it. Flakes is handled above, ahead of `searching`, for the same
          // reason with a different shadow.
          : root.model.tab === 2 ? "no packages in your nixarchy selection yet \u2014 / to search nixpkgs"
          : root.model.tab === 3 ? "type to search NixOS options"
          : root.model.indexTab ? "type to search nixpkgs"
          : "nothing here yet"
      textFormat: Text.PlainText
      font.family: root.fontFamily
      font.pixelSize: root.px(Style.font.body)
      color: root.dim
    }
  }

  // ---- footer ---------------------------------------------------------

  Column {
    id: footer
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    spacing: Style.space(4)

    Rectangle {
      width: parent.width
      height: Math.max(1, Style.space(1))
      color: root.dim
      opacity: 0.25
    }

    // Whatever a writer last said. These are the refusals -- an id that
    // drifted out of the catalogue, a name nixpkgs does not carry -- so
    // they are shown rather than swallowed.
    //
    // Shown to the END. This was capped at three lines and elided, which
    // swallowed the part that mattered most: the writers report one
    // wrapped row per package and then their consequence -- the line
    // saying a commented allowUnfreePredicate was scaffolded, which is a
    // licence-policy edit -- so on a multi-package add the consequence was
    // the first thing off the bottom. It scrolls now instead: bounded, so
    // a long report cannot push the list, but never truncated.
    Flickable {
      // Inset to the same column the rows use (their delegate's
      // leftMargin above), so the card has one left edge rather than a
      // list that starts here and a footer that starts there.
      x: Style.space(10)
      width: parent.width - Style.space(20)
      visible: root.model && root.model.message.length > 0
      // topMargin is space BEFORE the content, so it has to be counted in
      // the height as well as the content -- sized without it, the last
      // line is clipped by exactly the margin.
      height: Math.min(topMargin + messageText.implicitHeight, root.rowHeight * 4)
      contentHeight: messageText.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      topMargin: Style.space(6)

      Text {
        id: messageText
        width: parent.width
        text: root.model ? root.model.message : ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: root.px(Style.font.caption)
        color: root.dim
      }
    }

    Item {
      width: parent.width
      height: root.px(Style.font.caption) + Style.space(10)

      Text {
        anchors {
          left: parent.left; leftMargin: Style.space(10)
          verticalCenter: parent.verticalCenter
        }
        text: {
          if (!root.model) return ""
          if (root.model.queued === 0) return "nothing queued"
          var n = root.model.queued
          return n + (n === 1 ? " change queued" : " changes queued")
              + (root.model.neverApplied ? " \u00b7 never applied" : "")
        }
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: root.px(Style.font.caption)
        color: root.model && root.model.queued > 0 ? Color.menu.selectedText : root.dim
      }

      // A stale index has no unfree or broken flags in it at all, so every
      // package on it reads as free. Said plainly, with the key that fixes
      // it, rather than left for the user to discover after a rebuild.
      Text {
        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
        visible: root.model && root.model.indexStale
        text: "index stale \u2014 r to rebuild"
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: root.px(Style.font.caption)
        color: Color.urgent
      }

      Text {
        anchors {
          right: parent.right; rightMargin: Style.space(10)
          verticalCenter: parent.verticalCenter
        }
        text: root.model && root.model.busy ? "working\u2026" : "? keys   a apply   esc close"
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: root.px(Style.font.caption)
        color: root.dim
      }
    }
  }
}
