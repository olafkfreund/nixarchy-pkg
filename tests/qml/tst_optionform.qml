// OptionForm, driven through the Process stub: the test delivers what the
// adapter would have answered.
import QtQuick
import QtTest

TestCase {
  name: "OptionForm"
  when: windowShown

  QtObject {
    id: fakeModel
    property string script: "nixarchy-pkg"
    property bool applying: false
    property bool busy: false
    property string message: ""
    function refresh() {}
  }

  // In the TestCase's own window: keyClick sends keys there, not to a Window
  // of the test's making.
  width: 800; height: 500
  // Stands in for the menu's list: it holds the keyboard before the form opens.
  Item { id: list; focus: true }
  OptionForm { id: form; anchors.fill: parent; model: fakeModel }

  // The form's describe Process: the stub child whose command names "describe".
  function describeProc() {
    for (var i = 0; i < form.data.length; i++) {
      var c = form.data[i]
      if (c && c.command !== undefined && c.deliver && String(c.command).indexOf("describe") >= 0)
        return c
    }
    return null
  }

  function writeProcess() {
    for (var i = 0; i < form.data.length; i++) {
      var c = form.data[i]
      if (c && c.command !== undefined && c.deliver && c !== describeProc()) return c
    }
    return null
  }

  function init() {
    if (form.open) form.finish()
    list.forceActiveFocus()
  }

  function test_opens_and_seeds_a_boolean() {
    form.begin({ path: "t.bool" })
    verify(form.open)
    var p = describeProc()
    verify(p !== null)
    p.deliver(JSON.stringify({ ok: true, path: "t.bool", widget: "boolean",
                               type: "boolean", default: "false", current: { state: "set", value: "true" } }))
    compare(form.widget, "boolean")
    compare(form.boolValue, true)
    compare(form.touched, false)
    compare(form.nixValue(), "")
  }

  function test_markup_is_readable_plain_text() {
    form.begin({ path: "t.bool" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "t.bool", widget: "boolean",
      description: "see {option}`a.b` here\n\n::: {.note}\nbe careful\n:::\n\n::: {.warning}\nwatch out\n:::" }))
    var shown = form.reflow(form.option.description)
    verify(shown.indexOf("see a.b here") >= 0)
    verify(shown.indexOf("Note:") >= 0)
    verify(shown.indexOf("Warning:") >= 0)
    verify(shown.indexOf(":::") < 0)
  }

  function test_admonition_forms_become_labels() {
    var shown = form.reflow("::: {.tip}\nuse it\n:::\n\n  :::{.important}\nreally\n  :::\n\n:::{.caution}\ncare\n:::")
    verify(shown.indexOf("Tip:") >= 0)
    verify(shown.indexOf("Important:") >= 0)
    verify(shown.indexOf("Caution:") >= 0)
    verify(shown.indexOf(":::") < 0)
  }

  function test_read_only_refuses_a_write() {
    form.begin({ path: "t.ro" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "t.ro", widget: "boolean",
      type: "boolean", default: "false", readOnly: true, current: { state: "absent" } }))
    form.boolValue = true
    form.touched = true
    var writer = writeProcess()
    verify(writer !== null)
    compare(writer.command.length, 0)
    form.commit()
    verify(form.error.indexOf("read-only") >= 0)
    verify(!fakeModel.busy)
    compare(writer.command.length, 0)
    verify(form.open)
  }

  // #76: on a system with no options.json, describe answers ok:false. The
  // form shows the reason and must still close on ESC.
  function test_escape_closes_a_form_whose_describe_failed() {
    form.begin({ path: "services.tailscale.enable" })
    verify(form.open)
    var p = describeProc()
    verify(p !== null, "found the describe process")
    p.deliver(JSON.stringify({ ok: false, error: "no options.json on this system -- it builds no manual" }))
    compare(form.error, "no options.json on this system -- it builds no manual")
    keyClick(Qt.Key_Escape)
    verify(!form.open, "ESC closed the form")
  }

  // The same when describe dies without answering.
  function test_escape_closes_a_form_whose_describe_died() {
    form.begin({ path: "services.tailscale.enable" })
    describeProc().finish(1)
    verify(form.error.length > 0)
    keyClick(Qt.Key_Escape)
    verify(!form.open)
  }

  // #62: scope travels with the row, and defaults to system.
  function test_describe_passes_the_rows_scope() {
    form.begin({ path: "programs.git.enable", scope: "user" })
    compare(describeProc().command.join(" "), "nixarchy-pkg opt describe --scope user programs.git.enable")
    form.finish()
    form.begin({ path: "programs.git.enable" })
    compare(describeProc().command.join(" "), "nixarchy-pkg opt describe --scope system programs.git.enable")
  }

  function test_integer_focus_steps_and_bounds() {
    form.begin({ path: "t.port" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "t.port", widget: "integer",
      default: "22", min: "0", max: "65535", current: { state: "absent" } }))
    var field = findChild(form, "integerField")
    verify(field !== null)
    tryCompare(field, "activeFocus", true)
    field.text = "65535"
    keyClick(Qt.Key_Up)
    compare(field.text, "65535")
    field.text = "70000"
    form.commit()
    verify(form.error.indexOf("outside") >= 0)
    compare(writeProcess().command.length, 0)
    form.option = { widget: "integer", min: "-9223372036854775808", max: "9223372036854775807", current: { state: "absent" } }
    field.text = "9007199254740993"
    keyClick(Qt.Key_Up)
    compare(field.text, "9007199254740994")
    field.text = "0"
    keyClick(Qt.Key_Down)
    compare(field.text, "-1")
  }

  function test_delete_twice_removes_and_empty_string_arms() {
    form.begin({ path: "t.str" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "t.str", widget: "string",
      current: { state: "set", value: "\"old\"" } }))
    var field = findChild(form, "textField")
    tryCompare(field, "activeFocus", true)
    var writer = writeProcess()
    keyClick(Qt.Key_Delete)
    verify(form.armedRemove)
    compare(writer.command.length, 0)
    keyClick(Qt.Key_Delete)
    compare(writer.command.slice(1, 3).join(" "), "opt remove")
    writer.deliver(JSON.stringify({ ok: true }))
    form.begin({ path: "t.str" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "t.str", widget: "string",
      current: { state: "set", value: "\"old\"" } }))
    field.text = ""
    keyClick(Qt.Key_Return)
    verify(form.armedRemove)
    form.finish()
    form.begin({ path: "t.str" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "t.str", widget: "string",
      current: { state: "set", value: "\"old\"" } }))
    writer.command = []
    keyClick(Qt.Key_Return)
    verify(!form.armedRemove)
    compare(writer.command.length, 0)
  }
}
