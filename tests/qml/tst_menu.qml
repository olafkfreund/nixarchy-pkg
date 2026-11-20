import QtQuick
import QtTest

TestCase {
  name: "Menu"
  when: windowShown
  width: 800; height: 600
  visible: true

  Component { id: menuC; Menu {} }
  property var menu: null
  property var pkg: null
  property var panel: null
  property var keys: null
  property var search: null
  property var form: null

  function walk(o, test, acc) {
    acc = acc || []
    if (!o) return acc
    if (test(o)) acc.push(o)
    var k = o.children || []
    for (var i = 0; i < k.length; i++) walk(k[i], test, acc)
    return acc
  }
  // The model is the shell's singleton, so the one test leaves behind is the
  // next one's starting state: put back what the cases touch.
  function resetModel() {
    var m = PkgModel
    m._writer.running = false; m._writer.command = []
    m._apply.running = false; m._applyTerm.running = false
    m._check.running = false; m._reader.running = false
    m._pending.running = false; m._inspector.running = false
    m.busy = false; m.applying = false; m.checkRunning = false
    m.applyLog = []; m.logDetached = false
    m.armingState = ""; m.armedKind = ""; m.armedApply = ""
    m.detailText = ""; m.message = ""; m.inspected = null
    m.pendingDeclare = null; m.checkResult = null
    if (m.naming) m.cancelNaming()
    m.setQuery(""); m.setTab(0); m.cursor = 0
  }
  function fresh() {
    resetModel()
    if (menu) { panel.contentItem.parent = null; menu.destroy() }
    menu = menuC.createObject(this)
    pkg = null; panel = null
    pkg = PkgModel
    for (var i = 0; i < menu.data.length; i++) {
      var d = menu.data[i]
      if (d && d.contentItem !== undefined) panel = d
    }
    panel.contentItem.parent = this
    panel.contentItem.anchors.fill = this
    keys = walk(panel.contentItem, function (o) { return String(o).indexOf("QQuickFocusScope") === 0 && o.children.length > 3 })[0]
    search = walk(keys, function (o) { return o.placeholderText !== undefined })[0]
    form = walk(keys, function (o) { return o.begin !== undefined && o.finish !== undefined })[0]
    menu.open("{}")
    wait(30)
    pkg._reader.deliver(JSON.stringify({ok:true, apps:[{id:"a",label:"A",kind:"app",enabled:false},{id:"b",label:"B",kind:"app",enabled:false},{id:"c",label:"C",kind:"app",enabled:false}],services:[],packages:[],options:[],drafts:[]}))
  }
  function cleanup() {
    if (menu) { panel.contentItem.parent = null; menu.destroy() }
    menu = null; pkg = null; panel = null; keys = null; search = null; form = null
    resetModel()
  }
  function plainFlick() { return walk(keys, function (o) { return String(o).indexOf("QQuickFlickable") === 0 && o.visible && o.parent === keys })[0] }
  function longText() { var a = []; for (var i = 0; i < 120; i++) a.push("line " + i); return a.join("\n") }
  function flick() { return walk(keys, function (o) { return o.followTail !== undefined })[0] }

  function test_a_open_form_owns_the_keyboard() {
    fresh()
    verify(keys.activeFocus)
    form.begin({ path: "services.x.enable" })
    verify(form.open)
    keyClick(Qt.Key_Down); keyClick(Qt.Key_J); keyClick(Qt.Key_Right); keyClick(Qt.Key_Question)
    keyClick(Qt.Key_A, Qt.ShiftModifier)
    compare(pkg.cursor, 0); compare(pkg.tab, 0); compare(menu.keysOpen, false); compare(pkg.armingState, "")
    keyClick(Qt.Key_Escape); verify(!form.open)
    wait(30)
    verify(keys.activeFocus && !search.activeFocus, "list has the keyboard again")
  }
  function test_b_key_sheet() {
    fresh()
    menu.keysOpen = true
    keyClick(Qt.Key_Down); compare(menu.keysOpen, true); compare(pkg.cursor, 0)
    keyClick(Qt.Key_X); compare(menu.keysOpen, false); compare(pkg.cursor, 0)
  }
  function test_c_detail() {
    fresh()
    pkg.detailText = "d"
    keyClick(Qt.Key_Shift); compare(pkg.detailText, "d")
    keyClick(Qt.Key_Down); compare(pkg.detailText, "d")
    keyClick(Qt.Key_X); compare(pkg.detailText, ""); compare(pkg.cursor, 0)
  }
  function test_d_log() {
    fresh()
    pkg.applying = true; pkg._apply.running = true; pkg.applyLog = ["l1", "l2"]
    verify(pkg.showingLog)
    var lv = flick(); verify(lv, "log view")
    keyClick(Qt.Key_Down); compare(lv.followTail, false); compare(pkg.cursor, 0)
    keyClick(Qt.Key_End); compare(lv.followTail, true)
    keyClick(Qt.Key_X); compare(pkg.showingLog, true)
    keyClick(Qt.Key_Escape)
    compare(pkg.showingLog, false); compare(pkg.logDetached, true)
    compare(pkg.applying, true); compare(pkg._apply.running, true)
  }
  function test_e_armed() {
    fresh()
    pkg.armingState = "armed"; pkg.armedKind = "here"; pkg.armedApply = "here"
    keyClick(Qt.Key_Shift); compare(pkg.armedApply, "here")
    keyClick(Qt.Key_Down); compare(pkg.armedApply, "")
    pkg.armingState = "armed"; pkg.armedKind = "here"; pkg.armedApply = "here"
    keyClick(Qt.Key_A)
    compare(pkg.applying, true, "A confirmed the armed apply")
  }
  function test_f_naming() {
    fresh()
    pkg.setTab(5); wait(30)
    verify(search.activeFocus, "flakes puts the keyboard in the field")
    pkg.inspected = { ok: true, ref: "github:o/r", rows: [] }
    search.text = "github:o/r"
    var s = pkg.beginNaming(); verify(pkg.naming)
    search.text = s
    keyClick(Qt.Key_Escape)
    compare(pkg.naming, false); compare(search.text, "github:o/r")
  }
  function test_g_search_field() {
    fresh()
    keyClick(Qt.Key_Slash); verify(search.activeFocus)
    keyClick(Qt.Key_L); compare(search.text, "l"); compare(pkg.tab, 0)
    keyClick(Qt.Key_Tab); compare(pkg.tab, 1); verify(!search.activeFocus); verify(keys.activeFocus)
  }
  function test_h_focus_tabs() {
    fresh()
    pkg.setTab(5); wait(30); verify(search.activeFocus)
    pkg.setTab(0); wait(30); verify(keys.activeFocus); verify(!search.activeFocus)
  }
  function test_i_escape_ladder() {
    fresh()
    keyClick(Qt.Key_Slash); keyClick(Qt.Key_X); compare(search.text, "x")
    keyClick(Qt.Key_Escape)
    compare(search.text, ""); verify(menu.opened); verify(keys.activeFocus && !search.activeFocus)
    keyClick(Qt.Key_Escape); compare(menu.opened, false)
  }
  function test_j_close_finishes_form() {
    fresh()
    form.begin({ path: "services.x.enable" }); menu.close()
    verify(!form.open); compare(menu.opened, false)
  }

  function test_k_search_hands_back_on_down() {
    fresh()
    keyClick(Qt.Key_Slash); verify(search.activeFocus)
    keyClick(Qt.Key_Down)
    verify(!search.activeFocus); verify(keys.activeFocus); compare(pkg.cursor, 1)
  }
  function test_l_search_return_hands_back() {
    fresh()
    keyClick(Qt.Key_Slash); keyClick(Qt.Key_Return)
    verify(!search.activeFocus); verify(keys.activeFocus)
    compare(pkg._writer.running, true)
  }

  function test_m_key_sheet_scrolls() {
    fresh()
    menu.keyText = longText(); menu.keysOpen = true
    var v = plainFlick(); verify(v, "key sheet view"); verify(v.contentHeight > v.height)
    keyClick(Qt.Key_Down); verify(v.contentY > 0); var y = v.contentY
    keyClick(Qt.Key_Up); verify(v.contentY < y)
    keyClick(Qt.Key_End); compare(v.contentY, v.contentHeight - v.height)
    keyClick(Qt.Key_Home); compare(v.contentY, 0)
    compare(menu.keysOpen, true); compare(pkg.cursor, 0)
  }
  function test_n_detail_scrolls() {
    fresh()
    pkg.detailText = longText()
    var v = plainFlick(); verify(v, "detail view"); verify(v.contentHeight > v.height)
    keyClick(Qt.Key_J); verify(v.contentY > 0)
    keyClick(Qt.Key_PageDown); verify(v.contentY > 0)
    keyClick(Qt.Key_Home); compare(v.contentY, 0)
    compare(pkg.detailText, longText()); compare(pkg.cursor, 0)
  }
  function test_o_armed_cancelled_by_a_non_moving_key() {
    fresh()
    pkg.armingState = "armed"; pkg.armedKind = "here"; pkg.armedApply = "here"
    verify(keys.activeFocus && !search.activeFocus)
    keyClick(Qt.Key_Question)
    compare(pkg.armedApply, ""); compare(pkg.armingState, "")
    menu.keysOpen = false
    pkg.armingState = "reading"
    keyClick(Qt.Key_Slash)
    compare(pkg.armingState, "")
  }
  function test_p_naming_return() {
    fresh()
    pkg.setTab(5); wait(30)
    pkg.inspected = { ok: true, ref: "github:o/r", rows: [] }
    search.text = "github:o/r"
    search.text = pkg.beginNaming(); search.text = "myname"
    pkg.busy = true
    keyClick(Qt.Key_Return)
    compare(pkg.naming, true); compare(search.text, "myname")
    pkg.busy = false
    keyClick(Qt.Key_Return)
    compare(pkg.naming, false); compare(search.text, "")
    compare(pkg._writer.command.slice(1).join(" "), "flake add myname github:o/r")
  }
  function test_q_search_forwards_up_and_enter() {
    fresh()
    pkg.cursor = 2
    keyClick(Qt.Key_Slash); verify(search.activeFocus)
    keyClick(Qt.Key_Up); verify(!search.activeFocus); compare(pkg.cursor, 1)
    keyClick(Qt.Key_Slash); verify(search.activeFocus)
    keyClick(Qt.Key_Enter); verify(!search.activeFocus); compare(pkg._writer.running, true)
  }
  function test_r_escape_ladder_in_full() {
    fresh()
    search.text = "x"
    pkg.inspected = { ok: true, ref: "github:o/r", rows: [] }
    pkg.checkRunning = true; pkg._check.running = true
    keyClick(Qt.Key_Escape)
    compare(pkg._check.running, false); verify(pkg.inspected !== null); compare(search.text, "x")
    pkg.checkRunning = false
    keyClick(Qt.Key_Escape)
    compare(pkg.inspected, null); compare(search.text, "x"); verify(menu.opened)
    keyClick(Qt.Key_Escape); compare(search.text, ""); verify(menu.opened)
    keyClick(Qt.Key_Escape); compare(menu.opened, false)
  }
  function test_s_reopens_fresh() {
    fresh()
    menu.close()
    verify(!keys.visible); compare(menu.opened, false)
    search.text = "x"; pkg.setQuery("x")
    menu.keysOpen = true; pkg.detailText = "detail"
    compare(pkg.tab, 0); compare(pkg.query, "x")
    menu.open("{}"); wait(30)
    compare(pkg.tab, 0); compare(search.text, ""); compare(pkg.query, "")
    compare(menu.keysOpen, false); compare(pkg.detailText, "")
    verify(keys.activeFocus); verify(!search.activeFocus)

    menu.close()
    pkg.setQuery("orphan")
    compare(search.text, ""); compare(pkg.query, "orphan")
    menu.open("{}"); wait(30)
    compare(pkg.query, "")

    menu.close()
    pkg.setTab(1); compare(pkg.tab, 1)
    menu.open("{}"); wait(30)
    compare(pkg.tab, 0)
  }
  function test_s2_message_is_per_view_but_a_late_result_survives_unload() {
    fresh()
    pkg.message = "armed text"
    menu.close(); compare(pkg.message, "", "a message belongs to the view that showed it")
    pkg.message = "applied"            // arrives while the menu is unloaded
    menu.open("{}"); wait(30)
    compare(pkg.message, "applied", "the next open shows the late result")
  }
  function test_s3_work_outlives_the_menu() {
    fresh()
    pkg.applying = true; pkg._apply.running = true; pkg._writer.running = true
    panel.contentItem.parent = null; menu.destroy(); menu = null
    wait(30)
    compare(PkgModel._apply.running, true); compare(PkgModel._writer.running, true)
    compare(PkgModel.applying, true)
  }
  function test_s4_armed_state_is_dropped_on_close_and_a_late_result_survives() {
    fresh()
    pkg.armingState = "armed"; pkg.armedKind = "here"; pkg.armedApply = "here"; pkg.message = "press a again"
    menu.close()
    compare(pkg.armingState, ""); compare(pkg.armedApply, ""); compare(pkg.message, "")
    pkg.message = "applied"
    menu.open("{}"); wait(30)
    compare(pkg.message, "applied", "open's reset does not disarm over a late result")
  }
  function test_s5_unload_without_close_drops_view_state() {
    fresh()
    pkg.armingState = "armed"; pkg.armedKind = "here"; pkg.armedApply = "here"; pkg.message = "press a again"
    panel.contentItem.parent = null; menu.destroy(); menu = null
    wait(30)
    compare(PkgModel.armingState, ""); compare(PkgModel.message, "")
  }
  function test_t_shift_a_starts_terminal_apply() {
    fresh()
    verify(keys.activeFocus && !search.activeFocus)
    keyClick(Qt.Key_A, Qt.ShiftModifier)
    compare(pkg.armingState, "reading"); compare(pkg.armedKind, "terminal")
  }
  function test_u_shift_return_declares_without_follows() {
    fresh()
    pkg.setTab(5); wait(30)
    pkg.inspected = { ok: true, ref: "path:/tool", nixosModules: [] }
    search.text = "path:/tool"
    search.text = pkg.beginNaming(); search.text = "tool"
    keyClick(Qt.Key_Return, Qt.ShiftModifier)
    compare(pkg._writer.command.slice(1), ["flake", "add", "--no-follows", "tool", "path:/tool"])
  }
  function test_v_u_twice_updates_declared_input() {
    fresh()
    pkg.setTab(5); wait(30)
    pkg.state = { flakeDir: "/f", flakeFound: true,
                  flakes: [{ name: "tool", url: "path:/tool", locked: true, mine: true, inspectable: true, flake: true }] }
    pkg.cursor = 1
    search.focus = false; keys.forceActiveFocus()
    keyClick(Qt.Key_U)
    keyClick(Qt.Key_U)
    compare(pkg._writer.command.slice(1), ["flake", "update", "tool"])
  }
  function test_w_ctrl_return_adds_user_package_only_in_search() {
    fresh()
    pkg.setTab(2)
    pkg.query = "git"; pkg.results = [{kind:"pkg", name:"git", scope:"system"}]
    pkg.userScope = {available:true, reason:""}
    keys.forceActiveFocus()
    keyClick(Qt.Key_Return, Qt.ControlModifier)
    compare(pkg._writer.command.slice(1), ["pkg", "add", "--scope", "user", "git"])
  }
  function test_x_ctrl_return_acts_as_return_elsewhere() {
    fresh()
    keyClick(Qt.Key_Return, Qt.ControlModifier)
    compare(pkg._writer.running, true)
    compare(pkg._writer.command.slice(1), ["toggle", "app", "a"])
  }
}
