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
  property real textScale: 1.0

  readonly property color fg: Color.menu.text
  readonly property color dim: Qt.darker(fg, 1.6)
  readonly property string fontFamily: Style.font.family

  readonly property real rowHeight: Math.round(Style.spacing.controlHeight * 1.1)
  readonly property real bodyHeight: header.height + list.contentHeightCapped + footer.height
                                     + Style.space(18)

  signal requestEdit(var row)

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
        required property int index
        required property string modelData
        readonly property bool current: root.model && root.model.tab === index
        width: label.implicitWidth
        height: header.height

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

  // ---- the list -------------------------------------------------------

  ListView {
    id: list
    anchors {
      top: header.bottom; topMargin: Style.space(10)
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

    readonly property real contentHeightCapped:
      Math.min(contentHeight, root.maxHeight > 0 ? root.maxHeight * 0.7 : contentHeight)

    delegate: Rectangle {
      required property int index
      required property var modelData
      readonly property bool current: index === list.currentIndex

      width: list.width
      height: root.rowHeight
      color: current ? Color.menu.selectedBackground : "transparent"

      MouseArea {
        anchors.fill: parent
        onClicked: { if (root.model) { root.model.cursor = index; root.model.activate() } }
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
          text: modelData.enabled === undefined ? "·"
                                                : (modelData.enabled ? "■" : "□")
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: root.px(Style.font.body)
          color: modelData.enabled ? Color.menu.selectedText : root.dim
        }

        Text {
          id: name
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.width * 0.42)
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
          : root.model.searching ? "nothing matches “" + root.model.query + "”"
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

    // Whatever a writer last said. These are the refusals -- an unfree
    // package under a policy that forbids it, an id that drifted out of
    // the catalogue -- so they are shown rather than swallowed.
    Text {
      width: parent.width
      visible: root.model && root.model.message.length > 0
      text: root.model ? root.model.message : ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      maximumLineCount: 3
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: root.px(Style.font.caption)
      color: root.dim
      topPadding: Style.space(6)
    }

    Item {
      width: parent.width
      height: root.px(Style.font.caption) + Style.space(10)

      Text {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: {
          if (!root.model) return ""
          if (root.model.queued === 0) return "nothing queued"
          var n = root.model.queued
          return n + (n === 1 ? " change queued" : " changes queued")
              + (root.model.neverApplied ? " · never applied" : "")
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
        text: "index stale — R to rebuild"
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: root.px(Style.font.caption)
        color: Color.urgent
      }

      Text {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: root.model && root.model.busy ? "working…" : "? keys   a apply   esc close"
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: root.px(Style.font.caption)
        color: root.dim
      }
    }
  }
}
