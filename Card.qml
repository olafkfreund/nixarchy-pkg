import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
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

  readonly property color fg: Commons.Color.menu.text
  // Alpha, not darkening: darkening inverts the hierarchy on light themes.
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property string fontFamily: Style.font.family
  // Through a typed property first, as `fg`/`dim` do: the test stub's
  // `Color.menu` holds plain strings, and a string has no .r/.g/.b/.a.
  readonly property color selectedBg: Commons.Color.menu.selectedBackground
  readonly property color hoverBackground: Qt.rgba(selectedBg.r, selectedBg.g, selectedBg.b, selectedBg.a * 0.5)
  // Alpha 0 of the same colour, not "transparent": a fade to #00000000 passes through grey.
  readonly property color restBackground: Qt.rgba(selectedBg.r, selectedBg.g, selectedBg.b, 0)
  readonly property bool waiting: Boolean(model && (model.busy || model.reindexing || model.inspecting || model.checkRunning))
  property real busyProgress: 0
  readonly property bool busyAnimating: busyAnim.running
  NumberAnimation on busyProgress {
    id: busyAnim
    from: 0; to: 1
    // A running animation keeps its starting duration; a 0 ms loop could spin when motion resumes.
    duration: 1100
    loops: Animation.Infinite
    // Only while someone can see it: the Card outlives a closed menu.
    running: root.waiting && !Style.reduceMotion && Boolean(root.Window.window && root.Window.window.visible)
  }
  // Apps and Services rows carry an icon; the other tabs don't.
  readonly property bool showIcons: root.model && root.model.tab <= 1

  // Queue rows say how much they matter: a conflict or a failed check is
  // urgent, other check results stand out, notes recede.
  function rowColor(row) {
    if (row.scope === "user" && model && !model.userScope.available) return dim
    if (row.kind === "declared" && row.mine === false) return dim
    if (!model || !model.queueTab) return fg
    if (row.kind === "conflict" || (row.kind === "check" && row.verdict === "fails"))
      return Commons.Color.urgent
    if (row.kind === "check") return Commons.Color.accent
    if (row.kind === "note" || row.kind === "writing") return dim
    return fg
  }

  // The tags a row draws: its own flags, then its channel when it has one.
  // Only Selection rows carry a channel, so no other tab's rows change (#71).
  function tagsOf(row) {
    return (row.flags || []).concat(row.channel ? [row.channel] : [])
      .concat(row.scope === "user" ? ["user"] : [])
  }

  // The row under the cursor, and what the pane beside the list says about
  // it. A search row brings its own preview, minus the key hints, which
  // belong to the footer. Apps and Services rows have none, so the pane
  // composes one from what the row already knows.
  readonly property var currentRow: root.model ? root.model.rowAt(root.model.cursor) : null
  readonly property string previewText: {
    const r = currentRow
    if (!r) return ""
    if (r.scope === "user" && root.model && !root.model.userScope.available)
      return root.model.userScope.reason
    if (typeof r.preview === "string")
      return r.preview.split("\n")
              .filter(l => !l.trim().startsWith("ctrl-")).join("\n")
    if (root.model && root.model.tab <= 1) {
      // Groups, blank line between: a missing field must not leave a gap.
      // The catalogue's label already ends "(Category)"; don't say it twice.
      const cat = r.category && (r.label || "").indexOf("(" + r.category + ")") < 0 ? r.category : ""
      return [[r.label, cat], [r.note], [r.line]]
             .map(g => g.filter(x => x).join("\n"))
             .filter(x => x).join("\n\n")
    }
    return ""
  }
  readonly property bool showPreview: previewText.length > 0 && width >= Style.space(760)

  readonly property real rowHeight: Math.round(Style.font.heading * 2.2)
  // Deliberately NOT derived from the list's contentHeight: the surface
  // sizes itself from this, the list sizes itself from the surface, and
  // reading the content back closes the circle. Qt reported that as a
  // binding loop and drew the card at whatever height it got to first.
  readonly property real bodyHeight: header.height + footer.height + Style.space(28)

  // What RETURN does, so a click cannot mean something else. It used to
  // call model.activate() directly, which on the Options tab is `opt
  // remove` -- clicking an option deleted it instead of opening its form.
  signal requestActivate(int index)

  // ---- tabs -----------------------------------------------------------

  Row {
    id: header
    objectName: "header"
    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: Style.font.heading + Style.space(14)
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
          id: tabMouse
          anchors.fill: parent
          hoverEnabled: true
          onClicked: if (root.model) root.model.setTab(tabItem.index)
        }

        Text {
          id: label
          anchors.verticalCenter: parent.verticalCenter
          text: {
            const n = root.model ? root.model.tabCount(tabItem.index) : ""
            return tabItem.modelData + (n ? " " + n : "")
          }
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          color: tabItem.current ? Commons.Color.menu.selectedText
               : tabMouse.containsMouse ? root.fg : root.dim
          Behavior on color {
            enabled: !Style.reduceMotion
            ColorAnimation { duration: Style.duration(120) }
          }
        }

        // The current tab is named by a rule under it rather than by a
        // filled pill: a pill is a second surface, and this is one. Flag pills
        // are the exception, because they are warnings.
        Rectangle {
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
          height: Math.max(1, Style.space(2))
          visible: parent.current
          color: Commons.Color.menu.selectedText
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
  //
  // An Item owns the height: a wrapping Text's implicitHeight depends on its
  // own geometry, so binding its height to it loops (#57).
  Item {
    id: scope
    objectName: "scope"
    anchors { top: header.bottom; left: parent.left; right: parent.right }
    visible: Boolean(root.model && root.model.tab === 2 && !root.model.searching)
    height: visible ? scopeText.implicitHeight + Style.space(6) : 0

    Text {
      id: scopeText
      width: parent.width
      text: "packages nixarchy manages \u2014 not everything installed"
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      color: root.dim
    }
  }

  // ---- the list -------------------------------------------------------

  ListView {
    id: list
    anchors {
      top: scope.bottom; topMargin: Style.space(10)
      left: parent.left; right: root.showPreview ? preview.left : parent.right
      rightMargin: root.showPreview ? Style.space(14) : 0
      bottom: footer.top
      bottomMargin: Style.space(8)
    }
    clip: true
    model: root.model ? root.model.rows() : []
    currentIndex: root.model ? root.model.cursor : 0
    // Any new rows array resets ListView's own currentIndex to 0, and the
    // binding above only re-runs when cursor changes (#75).
    onModelChanged: currentIndex = Qt.binding(function () { return root.model ? root.model.cursor : 0 })
    highlightMoveDuration: 0
    // Enough of the list stays on screen either side of the cursor that
    // arrowing down does not feel like it is dragging the view.
    preferredHighlightBegin: height * 0.25
    preferredHighlightEnd: height * 0.75
    highlightRangeMode: ListView.ApplyRange

    // Category headers on Apps and Services. A section takes no model index,
    // so cursor, rowAt and count are unaffected.
    section.property: root.model && root.model.tab < 2 ? "section" : ""
    section.delegate: Text {
      required property string section
      width: ListView.view ? ListView.view.width : 0
      height: Math.round(Style.font.title * 2)
      verticalAlignment: Text.AlignBottom
      leftPadding: Style.space(10)
      text: section
      textFormat: Text.PlainText
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      color: root.dim
    }

    delegate: Rectangle {
      required property int index
      required property var modelData
      readonly property bool current: index === list.currentIndex

      width: list.width
      height: root.rowHeight
      color: current ? Commons.Color.menu.selectedBackground
           : rowMouse.containsMouse ? root.hoverBackground : root.restBackground
      Behavior on color {
        enabled: !Style.reduceMotion
        ColorAnimation { duration: Style.duration(120) }
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
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
          width: Style.font.heading
          // A .settings row is the attrset that configures an app, not a
          // thing with two states, so it must not draw a box implying one.
          // Glyphs as \u escapes, so the source survives an editor or a
          // patch that mangles them.
          text: modelData.settings === true      ? "\u2261"
              : modelData.set === true           ? "\u25a0"
              : modelData.set === false          ? "\u25a1"
              : modelData.enabled === undefined  ? "\u00b7"
              : modelData.enabled                ? "\u25a0" : "\u25a1"
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          color: modelData.set === true || modelData.enabled ? Commons.Color.menu.selectedText : root.dim
        }

        // The column is reserved while the picture loads or is missing, so
        // rows don't shift as icons arrive.
        Image {
          id: icon
          visible: root.showIcons
          anchors.verticalCenter: parent.verticalCenter
          width: Style.font.heading
          height: Style.font.heading
          sourceSize: Qt.size(width, height)
          // iconPath(_, true) is "" for a missing icon. image://icon/ draws a
          // checkerboard instead, reports it Ready, and logs a warning per row.
          // A .settings row is not an app, so it never has one.
          source: root.showIcons && modelData.id && !modelData.settings
                  ? Quickshell.iconPath(modelData.id, true) : ""
          opacity: status === Image.Ready ? 1 : 0
          asynchronous: true
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
                 && !(modelData.kind === "declared" && modelData.mine === false)
                 ? Math.min(implicitWidth, parent.width)
                 : Math.min(implicitWidth, parent.width * 0.42)
          elide: Text.ElideRight
          text: modelData.text || modelData.label || modelData.name || modelData.attr
                || modelData.path || modelData.id || ""
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.weight: Font.Medium
          color: current ? Commons.Color.menu.selectedText : root.rowColor(modelData)
        }

        // unfree, broken, and the curated cross-reference: picking the raw
        // package gets a bare binary where the app row gets the module.
        // Worth saying before it is queued, not after it is built.
        // Wrapped so the summary below can subtract what the flags actually
        // take. `visible` is load-bearing, not cosmetic: a Row ignores an
        // invisible child when positioning, so with no flags the outer row
        // is back to three children and two gaps, which is what the
        // `? 3 : 2` below counts (#45).
        //
        // `modelData` here is the ROW, not a flag: the Repeater's delegate
        // declares `required property string modelData`, which shadows it
        // one level further in. Do not move this binding inside.
        Row {
          id: flags
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)
          visible: root.tagsOf(modelData).length > 0

          Repeater {
            model: root.tagsOf(modelData)
            Rectangle {
              required property string modelData
              readonly property color tone: modelData === "broken" ? Commons.Color.urgent
                                          : (modelData === "unfree" || modelData === "other") ? Commons.Color.accent
                                          : root.dim
              anchors.verticalCenter: parent.verticalCenter
              color: Qt.rgba(tone.r, tone.g, tone.b, 0.15)
              radius: Style.cornerRadius
              width: tag.implicitWidth + Style.space(12)
              height: tag.implicitHeight + Style.space(4)

              Text {
                id: tag
                anchors.centerIn: parent
                text: parent.modelData
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                color: parent.tone
              }
            }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          // Every term is something on this row: the name, the state glyph,
          // the flags, and one gap per boundary between them. The old
          // Style.space(40) was right for no arrangement of this row -- 20px
          // too generous with no flags and too mean with any -- because the
          // Row's anchors already exclude its margins, so subtracting them
          // again double-counted (#45). The icon is a term too, and an
          // invisible one takes no width and no gap.
          width: Math.max(0, parent.width - name.width - Style.font.heading
                             - (icon.visible ? icon.width : 0)
                             - flags.width
                             - Style.space(10) * ((flags.visible ? 3 : 2)
                                                  + (icon.visible ? 1 : 0)))
          elide: Text.ElideRight
          text: modelData.kind === "declared" && modelData.mine === false
              ? "(not written by this tool)"
              : modelData.type !== undefined && modelData.type !== ""
              ? (modelData.summary || "") + "  \u00b7  " + modelData.type
                + (modelData.set === true && typeof modelData.current === "string" ? "  =  " + modelData.current : "")
              : (modelData.version ? modelData.version + "  " : "")
                + (modelData.summary || modelData.note || modelData.type || "")
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          color: root.dim
        }
      }
    }

    // An empty list is a question, not a blank. It says which one.
    Text {
      objectName: "emptyHint"
      anchors.centerIn: parent
      visible: list.count === 0 || (root.model && root.model.flakeTab
               && list.count === 1 && root.model.rowAt(0)
               && root.model.rowAt(0).kind === "head")
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
      font.pixelSize: Style.font.heading
      color: root.dim
    }
  }

  // Wheel-scrolled only and never focused, so the keyboard stays on the list.
  Item {
    id: preview
    objectName: "preview"
    anchors {
      top: scope.bottom; topMargin: Style.space(10)
      bottom: footer.top; bottomMargin: Style.space(8)
      right: parent.right
    }
    width: Math.round(parent.width * 0.38)
    visible: root.showPreview

    Rectangle {
      width: 1
      anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
      color: root.dim
      opacity: 0.25
    }

    Flickable {
      id: flick
      anchors {
        top: parent.top; bottom: parent.bottom
        left: parent.left; leftMargin: Style.space(14)
        right: parent.right
      }
      clip: true
      contentHeight: body.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      Text {
        id: body
        width: flick.width
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: root.fg
        text: root.previewText
        // A new row opens at its top, not where the last one was scrolled to.
        onTextChanged: flick.contentY = 0
      }
    }
  }

  // ---- footer ---------------------------------------------------------

  Column {
    id: footer
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    spacing: Style.space(4)

    Item {
      objectName: "busyRule"
      width: parent.width
      height: Math.max(1, Style.space(1))
      clip: true

      Rectangle {
        objectName: "busyRuleBase"
        anchors.fill: parent
        color: root.waiting && Style.reduceMotion ? Commons.Color.menu.selectedText : root.dim
        opacity: root.waiting && Style.reduceMotion ? 1 : 0.25
      }
      Rectangle {
        objectName: "busySegment"
        width: parent.width / 5
        height: parent.height
        x: -width + root.busyProgress * (parent.width + width)
        visible: root.waiting && !Style.reduceMotion
        color: Commons.Color.menu.selectedText
      }
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
        font.pixelSize: Style.font.title
        color: root.dim
      }
    }

    Item {
      width: parent.width
      height: Style.font.title + Style.space(10)

      Text {
        id: queueText
        objectName: "queueStatus"
        anchors {
          left: parent.left; leftMargin: Style.space(10)
          right: indexAge.visible ? indexAge.left : optionsText.visible ? optionsText.left : hints.left
          rightMargin: Style.space(14)
          verticalCenter: parent.verticalCenter
        }
        // A long reason (an interrupted write names its files and both
        // commands) is shown in full above; here it must not run under the hints.
        elide: Text.ElideRight
        text: {
          if (!root.model) return ""
          if (root.model.queued === -1)
            return root.model.queueError ? "queue unknown -- " + root.model.queueError
                                         : "reading queue\u2026"
          if (root.model.queued === 0) return "nothing queued"
          var n = root.model.queued
          return n + (n === 1 ? " change queued" : " changes queued")
              + (root.model.neverApplied ? " \u00b7 never applied" : "")
        }
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: root.model && root.model.queued > 0 ? Commons.Color.menu.selectedText : root.dim
      }

      // A stale index has no unfree or broken flags in it at all, so every
      // package on it reads as free. Said plainly, with the key that fixes
      // it, rather than left for the user to discover after a rebuild.
      Text {
        id: indexAge
        objectName: "indexAge"
        // Between the queue status and the options status (or the hints);
        // the queue status stops where this begins.
        anchors {
          right: optionsText.visible ? optionsText.left : hints.left; rightMargin: Style.space(14)
          verticalCenter: parent.verticalCenter
        }
        width: Math.min(implicitWidth, parent.width * 0.35)
        elide: Text.ElideRight
        visible: root.model && root.model.indexStale
        text: root.model && typeof root.model.indexLine === "function"
              ? root.model.indexLine(Date.now()) : "index stale \u2014 r to rebuild"
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: Commons.Color.urgent
      }

      // Where the option list came from, so "your flake's" and "the system
      // manual's" are never mistaken for each other.
      Text {
        id: optionsText
        objectName: "optionsStatus"
        anchors {
          right: hints.left; rightMargin: Style.space(14)
          verticalCenter: parent.verticalCenter
        }
        visible: text !== ""
        text: root.model ? String(root.model.optionsStatus || "") : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width * 0.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: root.model && root.model.optionsError ? Commons.Color.urgent : root.dim
      }

      Text {
        id: hints
        objectName: "hints"
        anchors {
          right: parent.right; rightMargin: Style.space(10)
          verticalCenter: parent.verticalCenter
        }
        text: root.model && (root.model.busy || root.model.reindexing) ? "working\u2026" : "? keys   a apply   esc close"
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: root.dim
      }
    }
  }
}
