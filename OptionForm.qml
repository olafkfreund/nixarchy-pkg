import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One NixOS option, with a widget chosen from its declared type.
//
// The widgets are the shell's own -- Toggle, TextField,
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
  property bool armedRemove: false

  signal closed()

  visible: open

  // A value already set in apps.nix that the type's widget cannot hold
  // exactly -- `lib.mkDefault true`, an expression -- opens in the scaffold
  // editor instead, as the text it is (#28).
  property bool forceScaffold: false
  readonly property string widget: forceScaffold ? "scaffold" : (option.widget || "")
  // What apps.nix says now: {state: absent | scaffold | set, value}.
  readonly property var current: option.current || ({ state: "absent" })
  // The path a write in flight is for. A result for any other form -- this
  // one closed and another opened meanwhile -- is not this form's (#28).
  property string writingPath: ""
  readonly property string fontFamily: Style.font.family
  // Alpha, not darkening: darkening inverts the hierarchy on light themes.
  readonly property color dim: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.6)


  // nixpkgs documentation is hard-wrapped prose -- real newlines at about
  // seventy columns, meant for a terminal. PlainText honours them, so the
  // text would wrap at the author's width rather than this card's. Single
  // breaks become spaces and blank lines stay as paragraph breaks, which
  // is what the source meant rather than what it contains.
  function reflow(s) {
    return String(s || "")
      .replace(/\r/g, "")
      .replace(/\{[a-z]+\}`([^`]*)`/g, "$1")
      .split("\n")
      .map(function (line) {
        var m = /^\s*:::\s*\{\.(\w+)\}\s*$/.exec(line)
        if (m) return m[1].charAt(0).toUpperCase() + m[1].slice(1) + ":"
        return /^\s*:::\s*$/.test(line) ? "" : line
      })
      .join("\n")
      .split(/\n[ \t]*\n/)
      .map(function (p) { return p.replace(/\n[ \t]*/g, " ").trim() })
      .filter(function (p) { return p.length > 0 })
      .join("\n\n")
  }

  Process {
    id: describe
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { data = null }
        // Late: the form closed, or moved on to another option.
        if (!root.open || (data && data.path && data.path !== root.path)) return
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
    // Same reason as writeProc: without this a describe that never answers
    // leaves the form open showing neither an option nor a reason (#43).
    onExited: function (code, status) {
      if (root.open && root.error === "" && !root.option.path)
        root.error = "the adapter ended without answering (exit " + code
                   + "); that option could not be read"
    }
  }

  Process {
    id: writeProc
    stdout: StdioCollector {
      onStreamFinished: {
        // First, whatever happens next: a form closed mid-write must not
        // leave the whole panel busy.
        if (root.model) root.model.busy = false
        var data
        try { data = JSON.parse(text) } catch (e) { data = null }
        if (!root.open || root.writingPath !== root.path) {
          // The form moved on, but the write still happened -- the adapter
          // had written the file before this answer was sent. The panel
          // must not go on showing pre-write state just because nobody is
          // watching it any more (#43).
          if (data && data.ok !== false && root.model) root.model.refresh()
          return
        }
        if (data === null) {
          // No answer is not a yes (#28).
          root.error = "the adapter gave no answer; nothing is known to be written"
          return
        }
        if (data.ok === false) {
          // The adapter parse-checks the file and restores its backup, so
          // a refusal here means nothing was written.
          root.error = String(data.error || data.message || "that value was refused")
          return
        }
        if (root.model) {
          if (data && data.message) root.model.message = String(data.message)
          root.model.refresh()
        }
        root.finish()
      }
    }
    // stdout finishing is the only thing the handler above waits on, so an
    // adapter that never writes -- missing, not executable, killed -- left
    // model.busy true and every later write refused "still writing" (#43).
    // Unblocking is not reporting success: the wording keeps #28's rule.
    onExited: function (code, status) {
      if (root.model) root.model.busy = false
      if (root.open && root.writingPath === root.path && root.error === "")
        root.error = "the adapter ended without answering (exit " + code
                   + "); nothing is known to be written"
    }
  }

  function begin(row) {
    var p = row ? (row.path || row.name || "") : ""
    if (!p) return
    root.path = p
    root.forceScaffold = false
    root.armedRemove = false
    root.error = ""
    root.option = ({})
    root.open = true
    describe.command = [root.model.script, "opt", "describe",
                        "--scope", (row && row.scope) || "system", p]
    describe.running = true
    // Take the keyboard now, not only in seed(): a describe that fails never
    // seeds, and the menu ignores keys while the form is open, so ESC went
    // nowhere (#76). seed() still moves focus on to the field it shows.
    root.forceActiveFocus()
  }

  function finish() {
    root.open = false
    root.option = ({})
    root.path = ""
    // And the path the write is answering to. Left set, a response that
    // arrived after the form closed still matched once the SAME option was
    // reopened, and closed the form the user was typing into (#43).
    root.writingPath = ""
    // Let go of the keyboard. A hidden Item keeps focus and still gets keys,
    // so a form closed while focused went on eating ESC (#27).
    textField.focus = false
    integerField.focus = false
    scaffoldField.focus = false
    root.focus = false
    root.closed()
  }

  // The starting state of each widget. Everything begins EMPTY on purpose,
  // except an enum, where there is no such thing as an empty choice and
  // the default is the honest opening position.
  function seed() {
    boolValue = option.default === "true"
    integerField.text = /^-?(0|[1-9][0-9]*)$/.test(String(option.default || "")) ? String(option.default) : ""
    textField.text = ""
    scaffoldField.text = option.example && option.example.length > 0
      ? option.example : (option.default || "")
    // At the option's own default, which is what the form claims to show.
    // Opening at zero made the displayed value wrong for every enum whose
    // default is not the first alternative, and j/k then moved relative to
    // a position nobody chose.
    enumIndex = 0
    var def = String(option.default || "")
    for (var i = 0; i < (option.choices || []).length; i++) {
      if (String(option.choices[i]) === def) { enumIndex = i; break }
    }
    // A value already in apps.nix is where the form opens, when the widget
    // can hold it exactly; anything else opens as its own text (#28).
    if (current.state === "set") {
      var v = String(current.value || "")
      var held = false
      switch (option.widget) {
        case "boolean":
          if (v === "true" || v === "false") { boolValue = v === "true"; held = true }
          break
        case "integer":
          if (/^-?(0|[1-9][0-9]*)$/.test(v)) { integerField.text = v; held = true }
          break
        case "enum":
          for (var j = 0; j < (option.choices || []).length; j++)
            if (String(option.choices[j]) === v) { enumIndex = j; held = true; break }
          break
        case "string":
          // Plain "..." only: no escapes, no interpolation to undo.
          if (/^"[^"\\$]*"$/.test(v)) { textField.text = v.slice(1, -1); held = true }
          break
      }
      if (!held) { forceScaffold = true; scaffoldField.text = v }
    } else if (option.widget === "integer" && option.default &&
               !/^-?(0|[1-9][0-9]*)$/.test(String(option.default))) {
      forceScaffold = true
    }
    touched = false
    // Whatever they are about to type into, focused -- otherwise the
    // keystrokes fall through to the surface behind and land in its
    // search box, which is exactly what happened the first time this
    // was driven from the keyboard.
    Qt.callLater(function () {
      // Closed in the meantime: taking the keyboard now would take it
      // from the list the form was closed back to.
      if (!root.open) return
      if (root.widget === "string")        textField.forceActiveFocus()
      else if (root.widget === "integer") integerField.forceActiveFocus()
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
      case "integer": return integerField.text
      case "string":
        if (textField.text.length === 0) return ""
        // A string or a path needs Nix quotes, and typing them is the sort
        // of homework this form exists to remove. Already-quoted input is
        // passed through untouched.
        if (textField.text.charAt(0) === "\"") return textField.text
        // Backslash first, or escaping the quote would then escape the
        // backslash this adds. A Nix string escapes both.
        return "\"" + textField.text
          .replace(/\\/g, "\\\\")
          .replace(/"/g, "\\\"")
          // and `${`, or a typed ${HOME} becomes an interpolation (#28)
          .replace(/\$\{/g, "\\${") + "\""
      default:
        return scaffoldField.text.trim()
    }
  }

  function commit() {
    // Read-only options are declared by their module and cannot be set.
    // Writing one produces a line that parses, queues, and is refused only
    // by the rebuild -- minutes later, with no clue which line did it.
    if (root.option.readOnly === true) {
      root.error = "this option is read-only: its module sets it, and a value here would only fail the rebuild"
      return
    }
    var value = nixValue()
    if (value.length === 0) {
      if (touched && current.state === "set" &&
          (widget === "string" || widget === "integer" || widget === "scaffold")) armRemove()
      else root.finish()
      return
    }
    if (widget === "integer" && value === "-") {
      root.error = "enter a complete integer before writing. Nothing was changed."
      return
    }
    if (widget === "integer" && /^-?(0|[1-9][0-9]*)$/.test(value) &&
        ((option.min != null && decimalLess(value, option.min)) ||
         (option.max != null && decimalLess(option.max, value)))) {
      root.error = path + " takes " + option.min + " to " + option.max + "; " + value + " is outside that. Nothing was changed."
      return
    }
    // One write at a time, and none while an apply could start: this used
    // to run beside the model's guard, so `a` could apply mid-write (#28).
    if (root.model.applying) { root.error = "an apply is running \u2014 wait for it to finish"; return }
    if (root.model.busy) { root.error = "still writing \u2014 try again in a moment"; return }
    // A line that is already there is changed in place, atomically; `set`
    // refuses it ("remove it first"), which is what `replace` exists for.
    var verb = (current.state === "set" || current.state === "scaffold") ? "replace" : "set"
    root.model.busy = true
    root.writingPath = root.path
    writeProc.command = [root.model.script, "opt", verb, root.path, value]
    writeProc.running = true
  }

  function decimalLess(a, b) {
    a = String(a); b = String(b)
    if (a === "-0") a = "0"
    if (b === "-0") b = "0"
    if (a.charAt(0) === "-" && b.charAt(0) !== "-") return true
    if (a.charAt(0) !== "-" && b.charAt(0) === "-") return false
    if (a.charAt(0) === "-") {
      a = a.slice(1); b = b.slice(1)
      return a.length !== b.length ? a.length > b.length : a > b
    }
    return a.length !== b.length ? a.length < b.length : a < b
  }

  function stepDecimal(value, direction) {
    if (!/^-?(0|[1-9][0-9]*)$/.test(value)) return value
    var negative = value.charAt(0) === "-"
    var digits = negative ? value.slice(1) : value
    var add = negative ? direction < 0 : direction > 0
    if (digits === "0" && !add) return direction < 0 ? "-1" : "1"
    var carry = 1, out = ""
    for (var i = digits.length - 1; i >= 0; i--) {
      var n = digits.charCodeAt(i) - 48 + (add ? carry : -carry)
      if (n === 10) { n = 0; carry = 1 }
      else if (n === -1) { n = 9; carry = 1 }
      else carry = 0
      out = String.fromCharCode(48 + n) + out
    }
    if (add && carry) out = "1" + out
    out = out.replace(/^0+(?=\d)/, "")
    return (negative && out !== "0" ? "-" : "") + out
  }

  function armRemove() {
    root.armedRemove = true
    root.error = "DEL again removes " + path + " from apps.nix; ESC keeps it"
  }

  function disarmRemove() {
    root.armedRemove = false
    if (root.error.indexOf("DEL again removes ") === 0) root.error = ""
  }

  function removeKey(event) {
    if (event.key !== Qt.Key_Delete || current.state !== "set" ||
        textField.activeFocus || integerField.activeFocus || scaffoldField.activeFocus) return false
    event.accepted = true
    if (!armedRemove) { armRemove(); return true }
    if (root.model.applying) { root.error = "an apply is running \u2014 wait for it to finish"; return true }
    if (root.model.busy) { root.error = "still writing \u2014 try again in a moment"; return true }
    root.model.busy = true
    root.writingPath = root.path
    writeProc.command = [root.model.script, "opt", "remove", root.path]
    writeProc.running = true
    return true
  }

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.menu.background
  }

  Keys.onPressed: function (event) {
    // A closed form handles nothing: every key belongs to the list.
    if (!root.open) return
    if (root.removeKey(event)) return
    root.disarmRemove()
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

  // A Flickable, not a bare Column: the form is as tall as the option it
  // describes, and an eight-line description with a scaffold box under it
  // outgrows the card once the desktop text size goes up. Anchored top,
  // left and right only, with nothing clipping it -- not this scope, not
  // the surface -- the overflow painted outside the border onto the scrim
  // (#38). Same shape as the build log in Menu.qml and the footer message
  // in Card.qml.
  Flickable {
    id: body
    anchors.fill: parent
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true

    Column {
      id: column
      // body.width, not parent.width: a Flickable positions its content
      // rather than anchoring it, and `parent` here is the content item,
      // whose width is not the Flickable's.
      width: body.width
      spacing: Style.space(10)

      Text {
        width: parent.width
        text: root.path
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        color: Commons.Color.menu.selectedText
      }

      Text {
        width: parent.width
        visible: (root.option.type || "").length > 0
        text: root.option.type || ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: root.dim
      }

      // The option's own documentation. Markdown out of nixpkgs, shown as
      // the plain text it is: this string is external and Qt will happily
      // fetch an <img src> out of the shell process if told it is rich text.
      Text {
        width: parent.width
        visible: (root.option.description || "").length > 0
        text: root.reflow(root.option.description)
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 8
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: Commons.Color.menu.text
      }

      Text {
        width: parent.width
        visible: (root.option.default || "").length > 0
        text: "default:  " + (root.option.default || "").replace(/\n/g, " ")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: root.dim
      }

      // What is there now, labelled as what it is: the expression written in
      // apps.nix, not the value NixOS ends up with.
      Text {
        width: parent.width
        visible: root.current.state !== "absent"
        text: root.current.state === "set"
          ? "set in apps.nix:  " + String(root.current.value || "")
          : "a scaffold for this is in apps.nix"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: Commons.Color.menu.text
      }

      Text {
        width: parent.width
        visible: root.option.choicesUnavailable === true
        text: "This type's alternatives are not listed in a form this can offer \u2014 write a Nix expression."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: root.dim
      }

      Text {
        objectName: "secretWarning"
        width: parent.width
        visible: root.option.sensitive === true
        text: "This value is copied into the Nix store, which every user on this machine can read."
          + (root.option.fileOption ? " " + root.option.fileOption
             + " reads it from a file at run time instead -- give it the path as a quoted string, \"/run/secrets/...\", so the file itself is not copied into the store." : "")
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: root.dim
      }

      // ---- the widget ---------------------------------------------------

      Toggle {
        visible: root.widget === "boolean"
        // The full path is the heading above; repeating it here only elides
        // it into something less readable than the heading already is.
        label: "value"
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

      TextField {
        id: integerField
        objectName: "integerField"
        visible: root.widget === "integer"
        width: parent.width
        validator: RegularExpressionValidator { regularExpression: /-?(0|[1-9][0-9]*)?/ }
        foreground: Commons.Color.menu.text
        onTextChanged: { root.touched = true; root.disarmRemove() }
        Keys.onPressed: function (event) {
          root.disarmRemove()
          if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            var next = root.stepDecimal(text, event.key === Qt.Key_Up ? 1 : -1)
            if ((root.option.min == null || !root.decimalLess(next, root.option.min)) &&
                (root.option.max == null || !root.decimalLess(root.option.max, next))) text = next
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.commit(); event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.finish(); event.accepted = true
          }
        }
      }

      TextField {
        id: textField
        objectName: "textField"
        visible: root.widget === "string"
        width: parent.width
        placeholderText: root.current.state === "set" ? "empty keeps the current value" : "leave empty to keep the default"
        foreground: Commons.Color.menu.text
        onTextChanged: { root.touched = true; root.disarmRemove() }
        Keys.onPressed: function (event) {
          root.disarmRemove()
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
          font.pixelSize: Style.font.title
          color: root.dim
        }

        BorderSurface {
          id: scaffoldBox
          width: parent.width
          // Room for a real expression. The examples this fallback exists to
          // show are multiline Nix -- services.postgresql.package's default
          // is a nine-line conditional -- and a single-line field could not
          // hold one, which made the fallback unusable for the very types it
          // was there for.
          height: Math.max(Style.font.heading * 6, scaffoldField.implicitHeight + Style.space(16))
          color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.06)
          radius: Style.cornerRadius
          borderSpec: Border.controlSpec(scaffoldField.activeFocus ? "focus" : "normal",
                                         Commons.Color.menu.text, Commons.Color.accent)

          Flickable {
            anchors.fill: parent
            anchors.margins: Style.space(8)
            contentWidth: width
            contentHeight: scaffoldField.implicitHeight
            clip: true

            TextEdit {
              id: scaffoldField
              objectName: "scaffoldField"
              width: parent.width
              wrapMode: TextEdit.Wrap
              selectByMouse: true
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              color: Commons.Color.menu.text
              selectionColor: Commons.Color.accent
              // seed() fills this and then clears `touched`, so the seed
              // itself never counts as an edit.
              onTextChanged: { root.touched = true; root.disarmRemove() }
              Keys.onPressed: function (event) {
                root.disarmRemove()
                if (event.key === Qt.Key_Escape) { root.finish(); event.accepted = true }
                // RETURN is a newline here, because the value may be several
                // lines. Ctrl+RETURN writes, the way any multiline editor
                // that also has a submit does it.
                else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                         && (event.modifiers & Qt.ControlModifier)) {
                  root.commit(); event.accepted = true
                }
              }
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: root.option.readOnly === true
        text: "read-only \u2014 this option is set by its own module"
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: Commons.Color.urgent
      }

      Text {
        width: parent.width
        visible: root.error.length > 0
        text: root.error
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: Commons.Color.urgent
      }

      Text {
        width: parent.width
        text: (root.widget === "boolean" ? "SPACE toggles   RETURN writes   ESC cancels"
            : root.widget === "enum"    ? "j / k choose    RETURN writes   ESC cancels"
            : root.widget === "scaffold"
              ? "CTRL+RETURN writes   ESC cancels   \u2014 RETURN is a newline, empty keeps the " + (root.current.state === "set" ? "current value" : "default")
              : "RETURN writes   ESC cancels   \u2014 empty keeps the " + (root.current.state === "set" ? "current value" : "default"))
              + (root.current.state === "set" ? "   DEL removes" : "")
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        color: root.dim
      }
    }
  }
}
