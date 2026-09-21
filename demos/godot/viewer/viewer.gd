extends Control
const Session = preload("res://core/session.gd")
const View = preload("res://ui/canvas.gd")
const Background = preload("res://ui/background_dialog.gd")
var background_dialog
var session = Session.new()
var view
var status_label: Label
var file_label: Label
var play_button: Button
var seek: HSlider
var frame_label: Label
var clip_select: OptionButton
var socket_select: OptionButton
var attachment_label: Label
var toggles: Dictionary = {}
var open_dialog: FileDialog
var attach_dialog: FileDialog
var color_dialog: ConfirmationDialog
var color_picker: ColorPicker
var color_index: SpinBox
var color_name: Label
var color_target: OptionButton
var color_reset: Button
var info_dialog: AcceptDialog
var info_text: TextEdit
var offsets = [{},{}]
var current: Dictionary = {}
var busy = false
var updating = false
var android_elapsed = 0.0
var android_intent_id = -1

func _ready():
	get_window().content_scale_size = Vector2i.ZERO
	if OS.get_name() == "Android":
		get_window().content_scale_factor = maxf(1.0,minf(get_window().size.x,get_window().size.y)/460.0)
	build_ui()
	get_window().title = "PAPNG Viewer"
	get_window().min_size = Vector2i(420,400)
	get_window().files_dropped.connect(func(paths): if not paths.is_empty(): open_path(paths[0]))
	session.start()
	for path in OS.get_cmdline_user_args():
		if not path.begins_with("--"): open_path(path); break
	if OS.get_cmdline_user_args().is_empty():
		for path in OS.get_cmdline_args():
			if path.get_extension().to_lower() in ["papng","png","apng"] and FileAccess.file_exists(path): open_path(path); break

func _exit_tree(): session.close()

func button(parent: Node, text: String, action: Callable, tip: String = "") -> Button:
	var b = Button.new(); b.text = text; b.tooltip_text = tip; b.custom_minimum_size.y = 42
	b.pressed.connect(action); parent.add_child(b); return b

func toggle(parent: Node, text: String, key: String, tip: String):
	var b = button(parent,text,func(): view.set(key,not view.get(key)); sync_toggle(key),tip)
	b.toggle_mode = true; toggles[key] = b

func sync_toggle(key: String):
	toggles[key].set_pressed_no_signal(view.get(key)); view.queue_redraw()

func menu(parent: Node, text: String, items: Array, handler: Callable):
	var b = MenuButton.new(); b.text = text; b.custom_minimum_size.y = 40; parent.add_child(b)
	for item in items: b.get_popup().add_item(item)
	b.get_popup().id_pressed.connect(handler)

func build_ui():
	var theme_resource = Theme.new(); theme_resource.default_font_size = 16
	var font = SystemFont.new(); font.font_names = PackedStringArray(["Noto Sans CJK KR","Noto Sans","sans-serif"])
	theme_resource.default_font = font; theme = theme_resource
	var background = ColorRect.new(); background.color = Color("202b3a"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var outer = MarginContainer.new(); outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: outer.add_theme_constant_override("margin_"+side,10)
	add_child(outer)
	var column = VBoxContainer.new(); outer.add_child(column)
	var menus = HBoxContainer.new(); column.add_child(menus)
	menu(menus,"파일",["열기…  Ctrl+O","파일 정보","끝내기"],file_menu)
	menu(menus,"보기",["화면에 맞춤  F","원래 크기  1","마스크 강조  M","헤더 힌트  H","소켓 위치·이름  S","배경…  Ctrl+B"],view_menu)
	menu(menus,"색상",["마스크 색상…  Ctrl+M","원본색으로 되돌리기"],func(id): show_colors() if id == 0 else reset_colors())
	menu(menus,"부속",["소켓에 연결할 파일…  Ctrl+L","연결 해제"],func(id): choose_attachment() if id == 0 else session.send({"type":"detach"}))
	file_label = Label.new(); file_label.text = "PAPNG Viewer"; file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; file_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; menus.add_child(file_label)
	var bar = HFlowContainer.new(); column.add_child(bar)
	button(bar,"열기",func(): open_dialog.popup_centered_ratio(0.8),"Ctrl+O · PAPNG / PNG / APNG")
	play_button = button(bar,"▶ 재생",func(): session.send({"type":"play"}),"Space")
	button(bar,"↺",func(): session.send({"type":"restart"}),"Home · 처음부터")
	button(bar,"→",func(): session.send({"type":"step"}),"Right · 다음 방문")
	button(bar,"색상",show_colors,"Ctrl+M · 마스크 색상각 변경")
	button(bar,"배경",show_background,"Ctrl+B · 체크무늬 / 단색 / 참고 이미지")
	toggle(bar,"마스크","highlight","M · 마스크 영역 강조")
	toggle(bar,"힌트","hints","H · 바운딩 박스 / pivot / 출력 힌트")
	toggle(bar,"소켓","sockets","S · 위치 / 이름 / 회전")
	button(bar,"맞춤",func(): view.fit(),"F")
	button(bar,"−",func(): view.zoom_by(0.8))
	button(bar,"+",func(): view.zoom_by(1.25))
	var options = HFlowContainer.new(); column.add_child(options)
	clip_select = OptionButton.new(); clip_select.add_item("전체 애니메이션"); clip_select.custom_minimum_size.y = 36; options.add_child(clip_select)
	clip_select.item_selected.connect(func(id): if not updating: session.send({"type":"clip","index":id-1}))
	socket_select = OptionButton.new(); socket_select.add_item("소켓 없음"); socket_select.custom_minimum_size.y = 36; options.add_child(socket_select)
	socket_select.item_selected.connect(func(id): view.socket_index = id; view.queue_redraw())
	attachment_label = Label.new(); attachment_label.text = "부속 없음"; attachment_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; attachment_label.custom_minimum_size.x = 130; options.add_child(attachment_label)
	view = View.new(); view.size_flags_vertical = Control.SIZE_EXPAND_FILL; view.custom_minimum_size.y = 100; column.add_child(view)
	var timeline = HBoxContainer.new(); column.add_child(timeline)
	seek = HSlider.new(); seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL; seek.custom_minimum_size.y = 36; seek.step = 1; timeline.add_child(seek)
	seek.value_changed.connect(func(value): if not updating: session.send({"type":"seek","frame":int(value)}))
	frame_label = Label.new(); frame_label.text = "—"; frame_label.custom_minimum_size.x = 120; timeline.add_child(frame_label)
	status_label = Label.new(); status_label.text = "파일을 열어 주세요. 휠로 확대, 드래그로 이동할 수 있습니다."; status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status_label.custom_minimum_size.y = 40; column.add_child(status_label)
	open_dialog = file_dialog(func(path): open_path(path)); attach_dialog = file_dialog(func(path): busy = true; session.send({"type":"attach","path":path}))
	info_dialog = AcceptDialog.new(); info_dialog.title = "파일 정보"; add_child(info_dialog)
	info_text = TextEdit.new(); info_text.editable = false; info_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; info_text.custom_minimum_size = Vector2(340,300); info_dialog.add_child(info_text)
	build_color_dialog()
	background_dialog = Background.new(); background_dialog.view = view; add_child(background_dialog)

func file_dialog(action: Callable) -> FileDialog:
	var dialog = FileDialog.new(); dialog.title = "이미지 열기"; dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	# Android providers frequently expose .papng as application/octet-stream.
	dialog.filters = PackedStringArray(["*.papng,*.png,*.apng;PAPNG / PNG / APNG", "*;모든 파일"])
	dialog.file_selected.connect(action); add_child(dialog); return dialog

func build_color_dialog():
	color_dialog = ConfirmationDialog.new(); color_dialog.title = "마스크 색상"; color_dialog.ok_button_text = "적용"; color_dialog.cancel_button_text = "닫기"; add_child(color_dialog)
	var column = VBoxContainer.new(); color_dialog.add_child(column)
	color_target = OptionButton.new(); color_target.add_item("원본 이미지"); color_target.add_item("부속 이미지"); column.add_child(color_target)
	color_target.item_selected.connect(func(_id): update_color_selection())
	color_index = SpinBox.new(); color_index.min_value = 0; color_index.step = 1; color_index.prefix = "마스크"; column.add_child(color_index)
	color_index.value_changed.connect(func(_value): update_color_selection())
	color_name = Label.new(); color_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(color_name)
	var note = Label.new(); note.text = "선택한 색의 색상각(H)을 사용합니다.\n원본의 명도·채도와 픽셀별 알파는 유지합니다.\n적용하면 재생을 멈추고 처음부터 복원합니다."; note.add_theme_font_size_override("font_size",14); column.add_child(note)
	color_picker = ColorPicker.new(); color_picker.edit_alpha = false; color_picker.can_add_swatches = false; color_picker.sampler_visible = false; color_picker.presets_visible = false; color_picker.sliders_visible = false; color_picker.hex_visible = false; color_picker.color_modes_visible = false; column.add_child(color_picker)
	color_reset = button(column,"원본색으로 되돌리기",func(): reset_colors(color_target.selected == 1); update_color_selection())
	color_dialog.confirmed.connect(apply_color)

func color_details() -> Dictionary:
	return view.child_info if color_target.selected == 1 else view.info

func update_color_selection():
	var details = color_details()
	var count = details.get("mask_count",0)
	color_index.set_block_signals(true); color_index.max_value = maxi(0,count-1); color_index.value = mini(color_index.value,color_index.max_value); color_index.set_block_signals(false)
	var id = int(color_index.value)
	var name = "마스크 %d" % id
	for group in details.get("groups",[]):
		if group.indices.size() == 1 and group.indices[0] == id: name = group.name; break
	var original: Color = details.get("colors",{}).get(id,Color(0.5,0.5,0.5))
	var usable = count > 0 and original.s > 0
	color_dialog.get_ok_button().disabled = not usable
	color_name.text = name if usable else name + " · 유효한 유색 픽셀이 없습니다"
	color_picker.color = Color.from_hsv(fposmod(original.h+offsets[color_target.selected].get(id,0.0)/360.0,1.0),original.s,original.v)
	if not view.info.is_empty() and color_target.selected == 0: session.send({"type":"select_mask","index":id})

func show_background(): background_dialog.open_settings()

func show_colors():
	if busy or view.info.is_empty(): return
	session.send({"type":"pause"})
	color_target.set_item_disabled(1,view.child_info.is_empty())
	if view.child_info.is_empty(): color_target.select(0)
	update_color_selection()
	color_dialog.popup_centered_clamped(Vector2i(440,540),0.92)

func apply_color():
	var details = color_details(); var id = int(color_index.value)
	var original: Color = details.get("colors",{}).get(id,Color(0.5,0.5,0.5))
	var delta = fposmod((color_picker.color.h-original.h)*360.0+180.0,360.0)-180.0
	offsets[color_target.selected][id] = delta
	session.send({"type":"hue","index":id,"offset":delta,"child":color_target.selected == 1})

func reset_colors(child: bool = false):
	offsets[1 if child else 0].clear()
	session.send({"type":"hue","reset":true,"child":child})

func choose_attachment():
	if busy or view.info.is_empty(): return
	if view.info.sockets.is_empty(): status_label.text = "이 이미지에는 연결할 소켓이 없습니다."; return
	attach_dialog.popup_centered_ratio(0.8)

func open_path(path: String):
	if path.begins_with("file://"): path = path.trim_prefix("file://").uri_decode()
	busy = true; view.clear(); current = {}; offsets = [{},{}]
	clip_select.select(0); view.socket_index = 0
	file_label.text = path.get_file(); status_label.text = "파일을 읽는 중…"; play_button.disabled = true
	color_dialog.hide(); info_dialog.hide()
	background_dialog.sync()
	session.send({"type":"open","path":path})

func show_info():
	if view.info.is_empty(): return
	info_text.text = "%s\n%s · %d × %d · %d 프레임\n마스크 %d개\n\n%s\n\nJSON5 메타데이터 (앞 65,536자)\n%s" % [view.info.path,view.info.kind,view.info.width,view.info.height,view.info.frames,view.info.mask_count,"\n".join(current.get("warnings",[])),view.info.metadata]
	info_dialog.popup_centered_clamped(Vector2i(700,540),0.9)

func _process(delta: float):
	for event in session.poll():
		if event.generation != session.generation: continue
		match event.type:
			"busy": busy = true; status_label.text = event.text
			"error": busy = false; status_label.text = event.text; play_button.disabled = view.info.is_empty()
			"info":
				if event.get("new_child",false): offsets[1] = {}
				busy = false; view.info = event.parent; view.child_info = event.child; view.queue_redraw(); background_dialog.sync()
				file_label.text = view.info.path.get_file(); get_window().title = file_label.text + " — PAPNG Viewer"
				updating = true
				var selected_clip = clip_select.selected
				clip_select.clear(); clip_select.add_item("전체 애니메이션")
				for c in view.info.clips: clip_select.add_item(c.name)
				clip_select.select(clampi(selected_clip,0,clip_select.item_count-1))
				socket_select.clear()
				for name in view.info.sockets: socket_select.add_item(name)
				if socket_select.item_count == 0: socket_select.add_item("소켓 없음")
				view.socket_index = clampi(view.socket_index,0,socket_select.item_count-1); socket_select.select(view.socket_index)
				attachment_label.text = "부속 없음" if view.child_info.is_empty() else "부속: " + view.child_info.path.get_file()
				updating = false
			"frame":
				current = event; busy = false; view.set_frame(event); play_button.disabled = false
				play_button.text = "Ⅱ 일시정지" if event.playing else "▶ 재생"
				updating = true; seek.min_value = event.start; seek.max_value = event.end; seek.value = maxi(event.start,event.frame); updating = false
				frame_label.text = "%d / %d" % [event.frame,view.info.get("frames",1)-1]
				var state = "첫 표시 프레임을 찾는 중 · Space로 재생/중단" if event.get("settling",false) else "재생 완료" if event.ended else "재생 중" if event.playing else "일시정지"
				status_label.text = "%s · %.2f ms" % [state,event.num*1000.0/event.den]
				if not event.warnings.is_empty(): status_label.text += "\n" + event.warnings[-1]
	android_elapsed += delta
	if OS.get_name() == "Android" and android_elapsed >= 0.3:
		android_elapsed = 0; poll_android_intent()

func poll_android_intent():
	if not Engine.has_singleton("AndroidRuntime"): return
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	var intent = activity.getIntent()
	var id = intent.hashCode()
	if id == android_intent_id: return
	android_intent_id = id
	if intent.getAction() == "android.intent.action.VIEW":
		var uri = intent.getData()
		if uri != null: open_path(uri.toString())
	elif intent.getAction() == "android.intent.action.SEND":
		var uri = intent.getParcelableExtra("android.intent.extra.STREAM")
		if uri != null: open_path(uri.toString())

func _unhandled_key_input(event):
	if not event is InputEventKey or not event.pressed or event.echo: return
	if color_dialog.visible or info_dialog.visible or open_dialog.visible or attach_dialog.visible or background_dialog.visible or background_dialog.file_dialog.visible: return
	var key = event.keycode
	if event.ctrl_pressed or event.meta_pressed:
		match key:
			KEY_O: open_dialog.popup_centered_ratio(0.8)
			KEY_M: show_colors()
			KEY_L: choose_attachment()
			KEY_B: show_background()
			_: return
	else:
		match key:
			KEY_SPACE: session.send({"type":"play"})
			KEY_HOME: session.send({"type":"restart"})
			KEY_RIGHT: session.send({"type":"step"})
			KEY_M,KEY_H,KEY_S:
				var flag = {KEY_M:"highlight",KEY_H:"hints",KEY_S:"sockets"}[key]; view.set(flag,not view.get(flag)); sync_toggle(flag)
			KEY_F: view.fit()
			KEY_1: view.actual()
			KEY_PLUS,KEY_EQUAL: view.zoom_by(1.25)
			KEY_MINUS: view.zoom_by(0.8)
			_: return
	get_viewport().set_input_as_handled()

func file_menu(id: int):
	match id:
		0: open_dialog.popup_centered_ratio(0.8)
		1: show_info()
		2: get_tree().quit()

func view_menu(id: int):
	match id:
		0: view.fit()
		1: view.actual()
		5: show_background()
		_:
			var key = ["highlight","hints","sockets"][id-2]
			view.set(key,not view.get(key)); sync_toggle(key)

func _shortcut_input(event):
	_unhandled_key_input(event)
