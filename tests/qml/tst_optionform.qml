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

  function writeProc() {
    for (var i = 0; i < form.data.length; i++) {
      var c = form.data[i]
      if (c && c.deliver && c.command.length > 2 && c.command[1] === "opt" && c.command[2] !== "describe") return c
    }
    return null
  }
  function walk(o, test, acc) {
    acc = acc || []; if (!o) return acc
    if (test(o)) acc.push(o)
    var k = o.children || []
    for (var i = 0; i < k.length; i++) walk(k[i], test, acc)
    return acc
  }
  function open(opt) {
    form.begin({ path: "p.q" })
    var o = { ok: true, path: "p.q" }
    for (var k in opt) o[k] = opt[k]
    describeProc().deliver(JSON.stringify(o))
    wait(20)
  }
  function init() {
    fakeModel.applying = false; fakeModel.busy = false
    var w = writeProc(); if (w) w.command = []

    if (form.open) form.finish()
    list.forceActiveFocus()
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

  function test_untouched_writes_nothing() {
    open({ widget: "boolean", default: "false" })
    keyClick(Qt.Key_Return)
    verify(!form.open); compare(fakeModel.busy, false); compare(writeProc(), null)
  }
  function test_touched_boolean_sets() {
    open({ widget: "boolean", default: "false" })
    keyClick(Qt.Key_Space); keyClick(Qt.Key_Return)
    compare(writeProc().command.slice(1).join(" "), "opt set p.q true")
    compare(fakeModel.busy, true)
  }
  function test_held_value_replaces() {
    open({ widget: "boolean", default: "false", current: { state: "set", value: "false" } })
    compare(form.boolValue, false)
    keyClick(Qt.Key_Space); keyClick(Qt.Key_Return)
    compare(writeProc().command.slice(1).join(" "), "opt replace p.q true")
  }
  function test_scaffold_state_replaces() {
    open({ widget: "boolean", default: "false", current: { state: "scaffold" } })
    keyClick(Qt.Key_Space); keyClick(Qt.Key_Return)
    compare(writeProc().command[2], "replace")
  }
  function test_unfit_value_opens_scaffold() {
    open({ widget: "integer", default: "1", current: { state: "set", value: "lib.mkDefault 5" } })
    compare(form.widget, "scaffold"); compare(form.forceScaffold, true)
    form.touched = true
    compare(form.nixValue(), "lib.mkDefault 5")
  }
  function test_fitting_value_stays_widget() {
    open({ widget: "integer", default: "1", current: { state: "set", value: "7" } })
    compare(form.widget, "integer"); compare(form.nixValue(), "")
    form.touched = true; compare(form.nixValue(), "7")
  }
  function test_refusals() {
    open({ widget: "boolean", default: "false", readOnly: true })
    keyClick(Qt.Key_Space); keyClick(Qt.Key_Return)
    verify(form.open); verify(form.error.indexOf("read-only") >= 0); compare(writeProc(), null); compare(fakeModel.busy, false)
    init(); open({ widget: "boolean", default: "false" })
    fakeModel.applying = true
    keyClick(Qt.Key_Space); keyClick(Qt.Key_Return)
    verify(form.error.indexOf("an apply is running") >= 0); compare(writeProc(), null)
    init(); open({ widget: "boolean", default: "false" })
    fakeModel.busy = true
    keyClick(Qt.Key_Space); keyClick(Qt.Key_Return)
    verify(form.error.indexOf("still writing") >= 0); compare(writeProc(), null)
    verify(form.open)
  }
  function test_enum_keys() {
    open({ widget: "enum", default: "b", choices: ["a", "b", "c"] })
    compare(form.enumIndex, 1)
    keyClick(Qt.Key_Down); compare(form.enumIndex, 2)
    keyClick(Qt.Key_J); compare(form.enumIndex, 0)
    keyClick(Qt.Key_K); compare(form.enumIndex, 2)
    keyClick(Qt.Key_Up); compare(form.enumIndex, 1)
    keyClick(Qt.Key_Return)
    compare(writeProc().command[4], "b")
  }
  function test_string_quoting() {
    open({ widget: "string", default: "" })
    var tf = walk(form, function (o) { return o.placeholderText !== undefined })[0]
    tf.text = "a\"b${HOME}"; form.touched = true
    compare(form.nixValue(), "\"a\\\"b\\${HOME}\"")
    tf.text = "\"x\""; compare(form.nixValue(), "\"x\"")
    tf.text = ""; compare(form.nixValue(), "")
  }

  function test_string_field_keys() {
    open({ widget: "string", default: "" })
    keyClick("h"); keyClick("i")
    keyClick(Qt.Key_Return)
    compare(writeProc().command.slice(1).join(" "), "opt set p.q \"hi\"")
    form.finish(); fakeModel.busy = false; writeProc().running = false; writeProc().command = []
    open({ widget: "string", default: "" })
    keyClick("h"); keyClick("i"); keyClick(Qt.Key_Escape)
    verify(!form.open); compare(writeProc(), null)
  }
  function test_scaffold_keys() {
    open({ widget: "boolean", default: "false", example: "x", current: { state: "set", value: "lib.mkDefault true" } })
    compare(form.widget, "scaffold")
    form.touched = true
    var ed = walk(form, function (o) { return String(o).indexOf("QQuickTextEdit") === 0 })[0]
    var before = ed.text.length
    keyClick(Qt.Key_Return)
    verify(form.open, "plain RETURN is a newline, not a write"); compare(writeProc(), null)
    compare(ed.text.length, before + 1)
    verify(form.nixValue().length > 0)
    keyClick(Qt.Key_Return, Qt.ControlModifier)
    compare(writeProc().command[2], "replace"); compare(writeProc().command[3], "p.q")
    form.finish(); fakeModel.busy = false; writeProc().running = false; writeProc().command = []
    open({ widget: "boolean", default: "false", current: { state: "set", value: "lib.mkDefault true" } })
    keyClick(Qt.Key_Escape); verify(!form.open); compare(writeProc(), null)
  }

  // #62: scope travels with the row, and defaults to system.
  function test_describe_passes_the_rows_scope() {
    form.begin({ path: "programs.git.enable", scope: "user" })
    compare(describeProc().command.join(" "), "nixarchy-pkg opt describe --scope user programs.git.enable")
    form.finish()
    form.begin({ path: "programs.git.enable" })
    compare(describeProc().command.join(" "), "nixarchy-pkg opt describe --scope system programs.git.enable")
  }
}
