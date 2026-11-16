// OptionForm, driven through the Process stub: the test delivers what the
// adapter would have answered.
import QtQuick
import QtTest

TestCase {
  name: "OptionForm"
  when: windowShown
  visible: true

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
  function searchProc() {
    for (var i = 0; i < form.data.length; i++) {
      var c = form.data[i]
      if (c && c.command && c.command[1] === "search") return c
    }
    return null
  }
  function packageSearchProcess() {
    for (var i = 0; i < form.data.length; i++) {
      var c = form.data[i]
      if (c && c.deliver && c !== describeProc() && c !== writeProcess()) return c
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
  function writeProcess() {
    for (var i = 0; i < form.data.length; i++) {
      var c = form.data[i]
      if (c && c.command !== undefined && c.deliver && c !== describeProc()) return c
    }
    return null
  }

  function init() {
    fakeModel.applying = false; fakeModel.busy = false
    var w = writeProc(); if (w) w.command = []

    if (form.open) form.finish()
    var s = searchProc(); if (s) { s.running = false; s.command = [] }
    list.forceActiveFocus()
  }

  function openTemplate(path) {
    form.begin({ path: path })
    describeProc().deliver(JSON.stringify({ ok: true, path: path, template: null,
      widget: "boolean", default: "false", current: { state: "absent" } }))
    wait(20)
    return walk(form, function (o) { return o.placeholderText && o.placeholderText.indexOf("name for ") === 0 })[0]
  }

  function test_template_names_and_concrete_current() {
    var field = openTemplate("users.users.<name>.shell")
    verify(field !== undefined)
    verify(field.activeFocus)
    keyClick(Qt.Key_Return)
    compare(form.error, "name every <name> first")
    field.text = "alice"
    form.touched = true
    form.commit()
    compare(form.path, "users.users.alice.shell")
    compare(describeProc().command.slice(-1)[0], form.path)
    compare(writeProc(), null)
    describeProc().deliver(JSON.stringify({ ok: true, path: form.path,
      template: "users.users.<name>.shell", widget: "boolean",
      current: { state: "set", value: "false" } }))
    compare(writeProc().command.slice(1).join(" "), "opt replace --scope system users.users.alice.shell false")
  }

  function test_quoted_and_keyword_names() {
    var field = openTemplate("fileSystems.<name>.options")
    field.text = "/mnt/usb drive"; form.touched = true; form.commit()
    compare(form.path, 'fileSystems."/mnt/usb drive".options')
    describeProc().deliver(JSON.stringify({ ok: true, path: form.path,
      template: "fileSystems.<name>.options", widget: "boolean", current: { state: "absent" } }))
    init()
    field = openTemplate("users.users.<name>.shell")
    field.text = "if"; form.touched = true; form.commit()
    compare(form.path, 'users.users."if".shell')
  }

  function test_invalid_name_refuses() {
    var field = openTemplate("users.users.<name>.shell")
    field.text = "a$b"; form.touched = true; form.commit()
    verify(form.error.indexOf("cannot contain") >= 0)
    compare(form.path, "users.users.<name>.shell")
    compare(writeProc(), null)
    for (var i = 0; i < 3; i++) {
      field.text = "a" + ["\u0001", "\r", "\u007f"][i] + "b"
      form.commit()
      verify(form.error.indexOf("cannot contain") >= 0)
      compare(form.path, "users.users.<name>.shell")
      compare(writeProc(), null)
    }
  }

  function test_name_tab_reaches_value_and_backtab_returns() {
    var field = openTemplate("users.users.<name>.shell")
    compare(field.placeholderText, "name for <name> 1 of 1: users")
    field.text = "alice"
    keyClick(Qt.Key_Tab)
    verify(form.activeFocus)
    keyClick(Qt.Key_Backtab)
    verify(field.activeFocus)
    keyClick(Qt.Key_Tab)
    keyClick(Qt.Key_Space)
    verify(form.touched, "SPACE touched the boolean after leaving the name field")
    keyClick(Qt.Key_Return)
    compare(form.path, "users.users.alice.shell")
    describeProc().deliver(JSON.stringify({ ok: true, path: form.path,
      template: "users.users.<name>.shell", widget: "boolean", current: { state: "absent" } }))
    compare(writeProcess().command.slice(1).join(" "), "opt set --scope system users.users.alice.shell true")
  }

  function test_two_name_placeholders_show_position_and_context() {
    var first = openTemplate("services.nginx.virtualHosts.<name>.locations.<name>.proxyPass")
    var fields = walk(form, function (o) { return o.placeholderText && o.placeholderText.indexOf("name for ") === 0 })
    compare(fields.length, 2)
    compare(first.placeholderText, "name for <name> 1 of 2: virtualHosts")
    compare(fields[1].placeholderText, "name for <name> 2 of 2: locations")
    first.text = "example"
    keyClick(Qt.Key_Tab)
    verify(fields[1].activeFocus)
  }

  function test_return_waits_for_concrete_describe() {
    var field = openTemplate("users.users.<name>.shell")
    field.text = "alice"
    form.boolValue = true
    form.touched = true
    form.commit()
    verify(form.awaitingConcrete)
    keyClick(Qt.Key_Return)
    compare(writeProcess().command.length, 0)
  }

  function test_failed_concrete_describe_drops_held_value() {
    var field = openTemplate("users.users.<name>.shell")
    field.text = "alice"
    form.boolValue = true
    form.touched = true
    form.commit()
    verify(form.awaitingConcrete)
    describeProc().deliver('{broken')
    compare(form.awaitingConcrete, false)
    compare(form.concreteValue, null)
    compare(form.path, "users.users.<name>.shell")
    keyClick(Qt.Key_Return)
    compare(writeProcess().command.length, 0)
  }

  function test_string_value_tab_and_backtab() {
    form.begin({ path: "users.users.<name>.description" })
    describeProc().deliver(JSON.stringify({ ok: true, path: form.path, template: null,
      widget: "string", current: { state: "absent" } }))
    var name = walk(form, function (o) { return o.placeholderText && o.placeholderText.indexOf("name for ") === 0 })[0]
    var value = findChild(form, "textField")
    wait(20)
    name.text = "alice"
    keyClick(Qt.Key_Tab)
    verify(value.activeFocus)
    keyClick(Qt.Key_Backtab)
    verify(name.activeFocus)
    keyClick(Qt.Key_Tab)
    for (var i = 0; i < 5; i++) keyClick([Qt.Key_H, Qt.Key_E, Qt.Key_L, Qt.Key_L, Qt.Key_O][i])
    keyClick(Qt.Key_Return)
    compare(form.path, "users.users.alice.description")
    describeProc().deliver(JSON.stringify({ ok: true, path: form.path,
      template: "users.users.<name>.description", widget: "string", current: { state: "absent" } }))
    compare(writeProcess().command.slice(1).join(" "), 'opt set --scope system users.users.alice.description "hello"')
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

  function test_sensitive_warning_does_not_block_write() {
    form.begin({ path: "t.password" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "t.password", widget: "string",
      sensitive: true, fileOption: "t.passwordFile", current: { state: "absent" } }))
    var warning = findChild(form, "secretWarning")
    verify(warning !== null)
    verify(warning.visible)
    verify(warning.text.indexOf("copied into the Nix store") >= 0)
    verify(warning.text.indexOf("t.passwordFile") >= 0)
    compare(warning.textFormat, Text.PlainText)
    var field = findChild(form, "textField")
    tryCompare(field, "activeFocus", true)
    field.text = "example"
    keyClick(Qt.Key_Return)
    compare(writeProcess().command.slice(1, 6).join(" "), "opt set --scope system t.password")
    writeProcess().deliver(JSON.stringify({ ok: true }))
    form.begin({ path: "t.bool" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "t.bool", widget: "boolean",
      sensitive: false, fileOption: null, current: { state: "absent" } }))
    verify(!warning.visible)
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

  function test_untouched_writes_nothing() {
    open({ widget: "boolean", default: "false" })
    keyClick(Qt.Key_Return)
    verify(!form.open); compare(fakeModel.busy, false); compare(writeProc(), null)
  }
  function test_touched_boolean_sets() {
    open({ widget: "boolean", default: "false" })
    keyClick(Qt.Key_Space); keyClick(Qt.Key_Return)
    compare(writeProc().command.slice(1).join(" "), "opt set --scope system p.q true")
    compare(fakeModel.busy, true)
  }
  function test_held_value_replaces() {
    open({ widget: "boolean", default: "false", current: { state: "set", value: "false" } })
    compare(form.boolValue, false)
    keyClick(Qt.Key_Space); keyClick(Qt.Key_Return)
    compare(writeProc().command.slice(1).join(" "), "opt replace --scope system p.q true")
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
    compare(writeProc().command[6], "b")
  }
  function test_string_quoting() {
    open({ widget: "string", default: "" })
    var tf = walk(form, function (o) { return o.objectName === "textField" })[0]
    tf.text = "a\"b${HOME}"; form.touched = true
    compare(form.nixValue(), "\"a\\\"b\\${HOME}\"")
    tf.text = "\"x\""; compare(form.nixValue(), "\"x\"")
    tf.text = ""; compare(form.nixValue(), "")
  }

  function test_list_and_multiline_values() {
    open({ widget: "list", item: "string" })
    var field = findChild(form, "scaffoldField")
    field.text = "a\nb"
    compare(form.nixValue(), '[ "a" "b" ]')
    field.text = 'console=ttyS0,115200n8'
    compare(form.nixValue(), '[ "console=ttyS0,115200n8" ]')
    field.text = "[ ]"
    compare(form.nixValue(), "[ ]")
    field.text = ""
    compare(form.nixValue(), "")
    init(); open({ widget: "list", item: "integer", min: "0", max: "65535" })
    field.text = "80\n443"
    compare(form.nixValue(), "[ 80 443 ]")
    field.text = "70000"
    form.commit()
    verify(form.error.indexOf("outside") >= 0)
    compare(writeProcess().command.length, 0)
    init(); open({ widget: "string", multiline: true })
    tryCompare(field, "activeFocus", true)
    field.text = 'a\n"${HOME}'
    compare(form.nixValue(), '"a\\n\\"\\${HOME}"')
  }

  function test_nullable_and_constraint() {
    open({ widget: "string", nullable: true, constraint: "absolute" })
    form.nullSelected = true; form.touched = true
    compare(form.nixValue(), "null")
    form.nullSelected = false
    var field = findChild(form, "textField")
    field.text = "rel/x"
    form.commit()
    verify(form.error.indexOf("absolute path") >= 0)
    compare(writeProcess().command.length, 0)
    init(); open({ widget: "list", item: "string", constraint: "absolute" })
    findChild(form, "scaffoldField").text = "/ok\nrel"
    form.commit()
    verify(form.error.indexOf("absolute path") >= 0)
    init(); open({ widget: "boolean", nullable: true, default: "null", current: { state: "set", value: "true" } })
    compare(form.nullSelected, false)
    compare(form.boolValue, true)
  }

  function test_null_skips_constraints_and_integer_list_checks() {
    for (var i = 0; i < 3; i++) {
      open({ widget: "string", nullable: true, default: "null",
        constraint: ["absolute", "nonEmpty", "noNewlineColon"][i] })
      form.nullSelected = true; form.touched = true
      form.commit()
      compare(writeProc().command.slice(1).join(" "), "opt set --scope system p.q null")
      init()
    }
    open({ widget: "list", item: "integer", nullable: true, default: "null" })
    form.nullSelected = true; form.touched = true
    form.commit()
    compare(writeProc().command.slice(1).join(" "), "opt set --scope system p.q null")
  }

  function test_nullable_integer_null_default_stays_integer() {
    open({ widget: "integer", nullable: true, default: "null" })
    compare(form.widget, "integer")
    compare(form.nullSelected, true)
  }

  function test_list_drops_blank_lines() {
    open({ widget: "list", item: "string" })
    findChild(form, "scaffoldField").text = "a\n\nb\n"
    compare(form.nixValue(), '[ "a" "b" ]')
    form.commit()
    compare(writeProc().command.slice(-1)[0], '[ "a" "b" ]')
    init(); open({ widget: "list", item: "integer" })
    findChild(form, "scaffoldField").text = "80\n\n443\n"
    form.commit()
    compare(writeProc().command.slice(-1)[0], "[ 80 443 ]")
  }

  function test_list_package_and_null_seeds() {
    open({ widget: "list", item: "string", current: { state: "set", value: '[ "a" "b" ]' } })
    compare(form.widget, "list")
    compare(findChild(form, "scaffoldField").text, "a\nb")
    init(); open({ widget: "list", item: "integer", current: { state: "set", value: "lib.mkForce [ 1 ]" } })
    compare(form.widget, "scaffold")
    init(); open({ widget: "list", item: "string", current: { state: "set", value: '[ "a\\nb" ]' } })
    compare(form.widget, "scaffold")
    init(); open({ widget: "list", item: "string", current: { state: "set", value: '[ "" ]' } })
    compare(form.widget, "scaffold")
    init(); open({ widget: "package", current: { state: "set", value: "pkgs.hello" } })
    compare(form.widget, "package")
    compare(findChild(form, "packageField").text, "hello")
    init(); open({ widget: "package", nullable: true, current: { state: "set", value: "null" } })
    compare(form.widget, "package")
    compare(form.nullSelected, true)
    form.touched = true
    compare(form.nixValue(), "null")
  }

  function test_package_search_selects_exact_result() {
    open({ widget: "package" })
    var field = findChild(form, "packageField")
    field.text = "hel"
    wait(350)
    var search = searchProc()
    verify(search !== null)
    compare(search.command.join(" "), "nixarchy-pkg search --kind pkg --limit 20 -- hel")
    search.deliver(JSON.stringify({ ok: true, rows: [
      { kind: "pkg", name: "hello", summary: "Greeting" },
      { kind: "pkg", name: "python3Packages.hello", summary: "Another greeting" }
    ] }))
    keyClick(Qt.Key_Down)
    compare(form.packageIndex, 1)
    keyClick(Qt.Key_Up)
    compare(form.packageIndex, 0)
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Return)
    compare(writeProc().command.slice(1).join(" "), "opt set --scope system p.q pkgs.python3Packages.hello")
  }

  function test_seeded_package_does_not_search_or_write() {
    open({ widget: "package", default: "pkgs.hello" })
    compare(findChild(form, "packageField").text, "hello")
    wait(350)
    compare(searchProc(), null)
    form.packageQuery = "hello"
    packageSearchProcess().deliver(JSON.stringify({ ok: true, rows: [
      { kind: "pkg", name: "hello-wayland" }, { kind: "pkg", name: "hello" }
    ] }))
    compare(form.packageResults.length, 2)
    keyClick(Qt.Key_Return)
    compare(writeProc(), null)
    verify(!form.open)
  }

  function test_package_search_keeps_plain_j_and_k_as_text() {
    open({ widget: "package" })
    var field = findChild(form, "packageField")
    field.text = "node"
    wait(350)
    searchProc().deliver(JSON.stringify({ ok: true, rows: [{ kind: "pkg", name: "nodejs" }] }))
    keyClick("j"); keyClick("s")
    compare(field.text, "nodejs")
    compare(form.packageIndex, 0)
    keyClick("k")
    compare(field.text, "nodejsk")
  }

  function test_stale_package_search_is_ignored() {
    open({ widget: "package" })
    var field = findChild(form, "packageField")
    field.text = "hel"
    wait(350)
    var search = searchProc()
    field.text = "node"
    wait(350)
    search.deliver(JSON.stringify({ ok: true, rows: [{ kind: "pkg", name: "hello" }] }))
    compare(form.packageResults.length, 0)
    tryCompare(search, "running", true)
    compare(search.command[search.command.length - 1], "node")
  }

  function test_ctrl_n_toggles_null_from_field() {
    open({ widget: "integer", nullable: true, default: "1" })
    var field = findChild(form, "integerField")
    tryCompare(field, "activeFocus", true)
    keyClick(Qt.Key_N, Qt.ControlModifier)
    compare(form.nullSelected, true)
    compare(form.touched, true)
    keyClick(Qt.Key_N, Qt.ControlModifier)
    compare(form.nullSelected, false)
    verify(walk(form, function (o) { return o.text && o.text.indexOf("CTRL+N") >= 0 }).length > 0)
  }

  function test_forced_multiline_scaffold_has_scaffold_hint() {
    open({ widget: "string", multiline: true, current: { state: "set", value: "lib.mkDefault \"x\"" } })
    compare(form.widget, "scaffold")
    verify(walk(form, function (o) {
      return o.visible && o.text && o.text.indexOf("This type has no one-word answer") >= 0
    }).length > 0)
  }

  function test_string_field_keys() {
    open({ widget: "string", default: "" })
    keyClick("h"); keyClick("i")
    keyClick(Qt.Key_Return)
    compare(writeProc().command.slice(1).join(" "), "opt set --scope system p.q \"hi\"")
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
    compare(writeProc().command[2], "replace"); compare(writeProc().command[5], "p.q")
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

  function test_late_describe_matches_scope_and_path() {
    form.begin({ path: "programs.git.enable", scope: "user" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "programs.git.enable", scope: "system", widget: "boolean" }))
    compare(form.option.path, undefined)
    describeProc().deliver(JSON.stringify({ ok: true, path: "programs.git.enable", scope: "user", widget: "boolean", current: { state: "absent" } }))
    compare(form.option.path, "programs.git.enable")
  }

  function test_user_scope_write_and_remove() {
    form.begin({ path: "p.q", scope: "user" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "p.q", scope: "user", widget: "boolean",
      default: "false", current: { state: "absent" } }))
    keyClick(Qt.Key_Space); keyClick(Qt.Key_Return)
    compare(writeProc().command.slice(1), ["opt", "set", "--scope", "user", "p.q", "true"])
    writeProc().deliver(JSON.stringify({ ok: true }))
    form.begin({ path: "p.q", scope: "user" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "p.q", scope: "user", widget: "boolean",
      current: { state: "set", value: "true" } }))
    keyClick(Qt.Key_Delete); keyClick(Qt.Key_Delete)
    compare(writeProc().command.slice(1), ["opt", "remove", "--scope", "user", "p.q"])
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

  function test_lone_minus_refuses_without_writing() {
    form.begin({ path: "t.port" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "t.port", widget: "integer",
      current: { state: "absent" } }))
    var field = findChild(form, "integerField")
    tryCompare(field, "activeFocus", true)
    field.text = "-"
    keyClick(Qt.Key_Return)
    verify(form.error.indexOf("complete integer") >= 0)
    compare(writeProcess().command.length, 0)
    verify(!fakeModel.busy)
  }

  function test_delete_twice_removes_and_empty_string_arms() {
    form.begin({ path: "t.bool" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "t.bool", widget: "boolean",
      current: { state: "set", value: "true" } }))
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
    var field = findChild(form, "textField")
    tryCompare(field, "activeFocus", true)
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

  function test_held_delete_does_not_arm_or_remove() {
    open({ widget: "boolean", current: { state: "set", value: "true" } })
    var writer = writeProcess()
    for (var i = 0; i < 2; i++) {
      var event = { key: Qt.Key_Delete, isAutoRepeat: true, accepted: false }
      compare(form.removeKey(event), true)
      compare(event.accepted, true)
      verify(!form.armedRemove)
      compare(writer.command.length, 0)
    }
  }

  function test_delete_edits_scaffold_without_arming_remove() {
    form.begin({ path: "t.multi" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "t.multi", widget: "scaffold",
      current: { state: "set", value: "abcde\nfgh" } }))
    var field = findChild(form, "scaffoldField")
    tryCompare(field, "activeFocus", true)
    var writer = writeProcess()
    field.cursorPosition = 2
    keyClick(Qt.Key_Home)
    keyClick(Qt.Key_Delete)
    keyClick(Qt.Key_Delete)
    compare(field.text, "cde\nfgh")
    verify(!form.armedRemove)
    compare(writer.command.length, 0)
  }

  function test_disarming_clears_only_remove_message() {
    form.begin({ path: "t.bool" })
    describeProc().deliver(JSON.stringify({ ok: true, path: "t.bool", widget: "boolean",
      current: { state: "set", value: "true" } }))
    form.forceActiveFocus()
    keyClick(Qt.Key_Delete)
    verify(form.armedRemove)
    verify(form.error.indexOf("DEL again removes ") === 0)
    keyClick(Qt.Key_Space)
    verify(!form.armedRemove)
    compare(form.error, "")
    form.error = "another refusal"
    keyClick(Qt.Key_Space)
    compare(form.error, "another refusal")
  }
}
