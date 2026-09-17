import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// One NixOS option, with a widget chosen from its declared type.
//
// The widgets are the shell's own -- Toggle, TextField, NumberField,
// Dropdown -- so an option here looks like every other control on this
// desktop and follows the theme without being told to.
//
// What it will and will not do is the important part. Booleans, enums,
// integers and simple strings get a real widget. Lists, `null or T`,
// attribute sets, submodules and functions do not: an option's value is
// arbitrary Nix, and a form that pretended otherwise would write
// plausible-looking wrong configuration. Those get the option's own
// example as a starting shape, in a field, for a person to edit.
//
// This is the same judgement nixarchy-search's own option picker makes,
// and deliberately so: the two write the same lines into the same file,
// and nixarchy-opt-remove has to be able to find either of them.
//
// A field left untouched writes NOTHING. A copied-out default is a line
// that reads as a choice and is not one.
//
// A FocusScope rather than an Item: the widgets that take typing need the
// keyboard on the field itself, and the ones that do not -- a checkbox, a
// list of choices -- need it on the scope, where the key handler lives.
FocusScope {
  id: root

  property var model: null
  property bool open: false
  property var option: ({})
  property string path: ""
  property string error: ""

  signal closed()

  visible: open

  readonly property string widget: option.widget || ""
  readonly property string fontFamily: Style.font.family

  Process {
    id: describe
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { data = null }
        if (!data || data.ok === false) {
          root.error = data && data.error ? String(data.error) : "could not read that option"
          root.option = ({})
          return
        }
        root.error = ""
        root.option = data
        root.seed()
      }
    }
  }

  Process {
    id: writeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { data = null }
        if (data && data.ok === false) {
          // The adapter parse-checks the file and restores its backup, so
          // a refusal here means nothing was written.
          root.error = String(data.error || "that value was refused")
          return
        }
        if (root.model) {
          if (data && data.message) root.model.message = String(data.message)
          root.model.refresh()
        }
        root.finish()
      }
    }
  }

  function begin(row) {
    var p = row ? (row.path || row.name || "") : ""
    if (!p) return
    root.path = p
    root.error = ""
    root.option = ({})
    root.open = true
    describe.command = [root.model.script, "opt", "describe", p]
    describe.running = true
  }

  function finish() {
    root.open = false
    root.option = ({})
    root.path = ""
    root.closed()
  }

  // The starting state of each widget. Everything begins EMPTY on purpose,
  // except an enum, where there is no such thing as an empty choice and
  // the default is the honest opening position.
  function seed() {
    boolValue = option.default === "true"
    numberField.value = parseInt(option.default, 10) || 0
    textField.text = ""
    scaffoldField.text = option.example && option.example.length > 0
      ? option.example : (option.default || "")
    enumIndex = 0
    touched = false
    // Whatever they are about to type into, focused -- otherwise the
    // keystrokes fall through to the surface behind and land in its
    // search box, which is exactly what happened the first time this
    // was driven from the keyboard.
    Qt.callLater(function () {
      if (root.widget === "string")        textField.forceActiveFocus()
      else if (root.widget === "scaffold") scaffoldField.forceActiveFocus()
      else                                 root.forceActiveFocus()
    })
  }

  property bool boolValue: false
  property int enumIndex: 0
  // Whether anyone has actually chosen anything. Without this a form that
  // was merely opened would write its own defaults back into the file.
  property bool touched: false

  readonly property var choices: option.choices || []

  // The widget's value as Nix source. Empty means "write nothing", which
  // the adapter understands and reports as keeping the default.
  function nixValue() {
    // Scaffolds are not exempt, though their field arrives pre-filled. The
    // seed is the option's own example or default, shown as a starting
    // shape to edit -- and writing it back unedited would put a line in
    // the file that reads as a decision and is not one. Nobody chose
    // "prohibit-password" by opening a form and pressing RETURN.
    if (!touched) return ""
    switch (widget) {
      case "boolean": return boolValue ? "true" : "false"
      case "enum":    return choices.length > 0 ? String(choices[enumIndex]) : ""
      case "integer": return String(numberField.value)
      case "string":
        if (textField.text.length === 0) return ""
        // A string or a path needs Nix quotes, and typing them is the sort
        // of homework this form exists to remove. Already-quoted input is
        // passed through untouched.
        if (textField.text.charAt(0) === "\"") return textField.text
        return "\"" + textField.text.replace(/"/g, "\\\"") + "\""
      default:
        return scaffoldField.text.trim()
    }
  }

  function commit() {
    var value = nixValue()
    if (value.length === 0) { root.finish(); return }
    writeProc.command = [root.model.script, "opt", "set", root.path, value]
    writeProc.running = true
  }

  Rectangle {
    anchors.fill: parent
    color: Color.menu.background
  }

  Keys.onPressed: function (event) {
    switch (event.key) {
      case Qt.Key_Escape:
        root.finish(); event.accepted = true; return
      case Qt.Key_Return:
      case Qt.Key_Enter:
        root.commit(); event.accepted = true; return
    }
    if (root.widget === "boolean" && event.key === Qt.Key_Space) {
      root.boolValue = !root.boolValue; root.touched = true
      event.accepted = true; return
    }
    if (root.widget === "enum" && root.choices.length > 0) {
      if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
        root.enumIndex = (root.enumIndex + 1) % root.choices.length
        root.touched = true; event.accepted = true; return
      }
      if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
        root.enumIndex = (root.enumIndex + root.choices.length - 1) % root.choices.length
        root.touched = true; event.accepted = true; return
      }
    }
  }

  Column {
    anchors { top: parent.top; left: parent.left; right: parent.right }
    spacing: Style.space(10)

    Text {
      width: parent.width
      text: root.path
      textFormat: Text.PlainText
      elide: Text.ElideMiddle
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      color: Color.menu.selectedText
    }

    Text {
      width: parent.width
      visible: (root.option.type || "").length > 0
      text: root.option.type || ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      color: Qt.darker(Color.menu.text, 1.5)
    }

    // The option's own documentation. Markdown out of nixpkgs, shown as
    // the plain text it is: this string is external and Qt will happily
    // fetch an <img src> out of the shell process if told it is rich text.
    Text {
      width: parent.width
      visible: (root.option.description || "").length > 0
      text: root.option.description || ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      maximumLineCount: 8
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      color: Color.menu.text
    }

    Text {
      width: parent.width
      visible: (root.option.default || "").length > 0
      text: "default:  " + (root.option.default || "").replace(/\n/g, " ")
      textFormat: Text.PlainText
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      color: Qt.darker(Color.menu.text, 1.5)
    }

    // ---- the widget ---------------------------------------------------

    Toggle {
      visible: root.widget === "boolean"
      label: root.path
      checked: root.boolValue
      onClicked: { root.boolValue = !root.boolValue; root.touched = true }
    }

    Dropdown {
      visible: root.widget === "enum"
      width: Math.min(parent.width, Style.spacing.dropdownWidth)
      label: "value"
      options: root.choices
      value: root.choices.length > 0 ? String(root.choices[root.enumIndex]) : ""
      onChanged: function (v) {
        for (var i = 0; i < root.choices.length; i++)
          if (String(root.choices[i]) === v) { root.enumIndex = i; root.touched = true }
      }
    }

    NumberField {
      id: numberField
      visible: root.widget === "integer"
      label: "value"
      from: -2147483647
      to: 2147483647
      onModified: root.touched = true
    }

    TextField {
      id: textField
      visible: root.widget === "string"
      width: parent.width
      placeholderText: "leave empty to keep the default"
      foreground: Color.menu.text
      onTextChanged: root.touched = true
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.commit(); event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.finish(); event.accepted = true
        }
      }
    }

    Column {
      visible: root.widget === "scaffold"
      width: parent.width
      spacing: Style.space(6)

      // Said plainly rather than hidden behind a widget that cannot mean
      // it: this type has no single answer to prompt for.
      Text {
        width: parent.width
        text: "This type has no one-word answer, so here is its own example to edit."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        color: Qt.darker(Color.menu.text, 1.4)
      }

      TextField {
        id: scaffoldField
        width: parent.width
        foreground: Color.menu.text
        // seed() fills this and then clears `touched`, so the seed itself
        // never counts as an edit -- only what is typed afterwards does.
        onTextChanged: root.touched = true
        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.commit(); event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.finish(); event.accepted = true
          }
        }
      }
    }

    Text {
      width: parent.width
      visible: root.error.length > 0
      text: root.error
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      color: Color.urgent
    }

    Text {
      width: parent.width
      text: root.widget === "boolean" ? "SPACE toggles   RETURN writes   ESC cancels"
          : root.widget === "enum"    ? "j / k choose    RETURN writes   ESC cancels"
          : "RETURN writes   ESC cancels   \u2014 empty keeps the default"
      textFormat: Text.PlainText
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      color: Qt.darker(Color.menu.text, 1.6)
    }
  }
}
