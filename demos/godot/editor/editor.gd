extends Control
const Model = preload("res://core/edit_model.gd")
const FrameEdit = preload("res://core/frame_edit.gd")
const Player = preload("res://core/player.gd")
const Doc = preload("res://core/document.gd")
const Parser = preload("res://core/json5.gd")
const Metadata = preload("res://core/metadata_edit.gd")
const Canvas = preload("res://ui/pixel_canvas.gd")
const Mini = preload("res://ui/minimap.gd")
const Inspector = preload("res://ui/inspector.gd")
const ImportDialog = preload("res://ui/import_dialog.gd")
const Importer = preload("res://core/import_image.gd")
const UI = preload("res://ui/widgets.gd")
const Icons = preload("res://ui/tool_icons.gd")
const BackgroundControls = preload("res://ui/background_controls.gd")
var background_controls
var background_file_dialog: FileDialog
var background_scroll: ScrollContainer
var background_toggle: CheckBox
var model = Model.new()
var canvas
var mini
var inspector
var player
var accessory
var accessory_player
var hues: Dictionary = {}
var clipboard: Dictionary = {}
var preview_dirty=true
var needs_refresh=false
var action_error=""
var tool_buttons: Dictionary = {}
var color_button: ColorPickerButton
var zoom_spin: SpinBox
var status: Label
var pixel_info: Label
var frame_info: Label
var title_info: Label
var play_button: Button
var timeline: HBoxContainer
var frame_spin: SpinBox
var open_dialog: FileDialog
var save_dialog: FileDialog
var import_file_dialog: FileDialog
var export_dialog: FileDialog
var accessory_dialog: FileDialog
var import_dialog
var raw_dialog: ConfirmationDialog
var raw_text: CodeEdit
var raw_mode="metadata"
var new_dialog: ConfirmationDialog
var new_width: SpinBox
var new_height: SpinBox
var discard_dialog: ConfirmationDialog
var pending_action: Callable
var notice_dialog: AcceptDialog
var busy_dialog: AcceptDialog
var busy_label: Label
var busy_cancel: Button
var worker: Thread
var job_kind=""
var job_started=0
var job_result: Dictionary = {}
var job_cancelled=false
var job_importer
var converter=""
var refs: Dictionary = {}
var reference_revision=-1
var refreshing=false
var preview_frame=-1
var tool_names={"pencil":"연필  B","erase":"지우개  E","fill":"채우기  G","pick":"스포이트  I","select":"선택  R","line":"직선  L","rect":"사각형  U","mask":"마스크  M","socket":"소켓  K"}

func _ready():
	get_tree().auto_accept_quit=false
	configure_window()
	var skin=Theme.new(); skin.default_font_size=14
	var font=SystemFont.new(); font.font_names=PackedStringArray(["Noto Sans CJK KR","Malgun Gothic","Noto Sans","sans-serif"]); skin.default_font=font
	var panel=StyleBoxFlat.new(); panel.bg_color=Color("202831"); panel.content_margin_left=8; panel.content_margin_right=8; panel.content_margin_top=6; panel.content_margin_bottom=6
	skin.set_stylebox("panel","PanelContainer",panel)
	var button=StyleBoxFlat.new(); button.bg_color=Color("33414e"); button.set_corner_radius_all(3); button.content_margin_left=10; button.content_margin_right=10; button.content_margin_top=5; button.content_margin_bottom=5
	skin.set_stylebox("normal","Button",button); var pressed=button.duplicate(); pressed.bg_color=Color("347c70"); skin.set_stylebox("pressed","Button",pressed)
	theme=skin
	var background=ColorRect.new(); background.color=Color("171e26"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(background)
	build_ui(); build_dialogs(); load_settings(); bind_model(model)
	get_viewport().files_dropped.connect(func(files): if not files.is_empty() and not busy(): request_open(files[0]))
	refresh_all(); canvas.fit.call_deferred()
	for arg in OS.get_cmdline_user_args()+OS.get_cmdline_args():
		if arg.get_extension().to_lower() in ["papng","apng","png"] and FileAccess.file_exists(arg): request_open.call_deferred(arg); break
func configure_window(): get_window().min_size=Vector2i(1100,760)
func make_importer(): return Importer.new()
func write_document(document, path: String) -> bool: return document.save_file(path)
func panel(parent: Node) -> VBoxContainer:
	var shell=PanelContainer.new(); parent.add_child(shell); var content=VBoxContainer.new(); shell.add_child(content); return content
func build_ui():
	var outer=VBoxContainer.new(); outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); outer.add_theme_constant_override("separation",4); add_child(outer)
	var menu=UI.row(outer)
	UI.button(menu,"새 파일",request_new,"Ctrl+N"); UI.button(menu,"열기…",func(): open_dialog.popup_centered_ratio(0.8),"Ctrl+O")
	UI.button(menu,"저장",save,"Ctrl+S"); UI.button(menu,"다른 이름…",func(): save_as(),"Ctrl+Shift+S")
	UI.button(menu,"이미지 가져오기…",func(): import_file_dialog.popup_centered_ratio(0.8),"Ctrl+I")
	UI.button(menu,"PNG 내보내기…",func(): export_dialog.popup_centered_ratio(0.75))
	UI.button(menu,"설정",show_settings); UI.button(menu,"도움말",show_help)
	title_info=UI.label(menu,""); title_info.size_flags_horizontal=Control.SIZE_EXPAND_FILL; title_info.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; title_info.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var toolbar=UI.row(outer)
	UI.button(toolbar,"↶ 실행 취소",undo,"Ctrl+Z"); UI.button(toolbar,"↷ 다시 실행",redo,"Ctrl+Y")
	UI.button(toolbar,"−",func(): canvas.set_zoom(canvas.zoom-1)); zoom_spin=UI.spin(toolbar,"배율",1,128); zoom_spin.suffix="×"; zoom_spin.value_changed.connect(func(value): canvas.set_zoom(int(value)))
	UI.button(toolbar,"+",func(): canvas.set_zoom(canvas.zoom+1)); UI.button(toolbar,"맞춤",func(): canvas.fit(),"F · 최소 1:1"); UI.button(toolbar,"1:1",func(): canvas.set_zoom(1),"1")
	for setting in [["격자","show_grid",true],["십자선","show_cross",true],["마스크 강조","show_mask",false],["힌트","show_hints",true],["소켓","show_sockets",true],["어니언","onion",false]]:
		var check=UI.check(toolbar,setting[0],setting[2]); var property=setting[1]
		check.toggled.connect(func(on): canvas.set(property,on); canvas.refresh())
	UI.button(toolbar,"배경…",show_background_settings)
	var workspace=HSplitContainer.new(); workspace.size_flags_vertical=Control.SIZE_EXPAND_FILL; workspace.split_offset=200; outer.add_child(workspace)
	var tool_scroll=ScrollContainer.new(); tool_scroll.custom_minimum_size.x=180; background_scroll=tool_scroll; tool_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; workspace.add_child(tool_scroll)
	var toolbox=panel(tool_scroll); toolbox.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	UI.label(toolbox,"도구")
	var group=ButtonGroup.new()
	var tools=HFlowContainer.new(); tools.name="ToolButtons"; toolbox.add_child(tools)
	for key in tool_names:
		var button=Icons.button(tools,key,tool_names[key].split("  ")[0],func(): select_tool(key),Icons.SHORTCUTS[key]); button.toggle_mode=true; button.button_group=group; tool_buttons[key]=button
	tool_buttons.pencil.button_pressed=true
	color_button=ColorPickerButton.new(); color_button.color=Color("ebbb71"); color_button.custom_minimum_size.y=40; toolbox.add_child(color_button)
	color_button.color_changed.connect(func(value): canvas.color=value)
	var brush=UI.spin(toolbox,"크기",1,64); brush.value=1; brush.value_changed.connect(func(value): canvas.brush=int(value))
	var actions=HFlowContainer.new(); actions.name="SelectionActions"; toolbox.add_child(actions)
	Icons.button(actions,"clear","선택 해제",func(): canvas.selection=Rect2i(); canvas.queue_redraw(),"Esc")
	Icons.button(actions,"cut","잘라내기",func(): copy(true),"Ctrl+X")
	Icons.button(actions,"copy","복사",func(): copy(false),"Ctrl+C")
	Icons.button(actions,"paste","붙여넣기",paste,"Ctrl+V")
	Icons.button(actions,"apply","배치 확정",func(): stop_playback(); canvas.apply_paste(),"Enter")
	UI.check(toolbox,"투명 픽셀도 교체").toggled.connect(func(value): canvas.replace_paste=value)
	var center_right=HSplitContainer.new(); center_right.size_flags_horizontal=Control.SIZE_EXPAND_FILL; center_right.split_offset=800; workspace.add_child(center_right)
	var center=VBoxContainer.new(); center.custom_minimum_size.x=320; center.size_flags_horizontal=Control.SIZE_EXPAND_FILL; center_right.add_child(center)
	frame_info=UI.label(center,""); frame_info.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	canvas=Canvas.new(); canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL; canvas.custom_minimum_size=Vector2(300,280); center.add_child(canvas)
	canvas.zoom_changed.connect(func(value): zoom_spin.set_value_no_signal(value)); canvas.cursor_changed.connect(cursor_info)
	canvas.picked.connect(func(value): color_button.color=value; canvas.color=value; select_tool("pencil"))
	canvas.message.connect(notify); canvas.socket_placed.connect(place_socket)
	background_toggle=UI.check(toolbox,"배경 설정",true)
	background_controls=BackgroundControls.new(); background_controls.host=self; toolbox.add_child(background_controls)
	background_toggle.toggled.connect(func(on): background_controls.visible=on)
	var right=VBoxContainer.new(); right.custom_minimum_size.x=310; center_right.add_child(right)
	inspector=Inspector.new(); inspector.host=self; inspector.size_flags_vertical=Control.SIZE_EXPAND_FILL; inspector.custom_minimum_size.y=245; right.add_child(inspector)
	var mini_box=panel(right); UI.label(mini_box,"1:1 미니맵 · 합성 결과 / 클릭으로 이동")
	var scroll=ScrollContainer.new(); scroll.custom_minimum_size.y=120; mini_box.add_child(scroll)
	mini=Mini.new(); scroll.add_child(mini); mini.centered.connect(func(point): canvas.pan=(Vector2(model.width,model.height)/2-point)*canvas.zoom; canvas.queue_redraw())
	pixel_info=UI.label(right,"커서: —\nRGBA: —\nHSV: —\n마스크: —"); pixel_info.custom_minimum_size.y=90; pixel_info.add_theme_font_size_override("font_size",13)
	var frames_panel=panel(outer); var frame_bar=UI.row(frames_panel)
	play_button=UI.button(frame_bar,"▶ 재생",func(): stop_playback() if canvas.playing else start_playback(),"Ctrl+Space")
	UI.button(frame_bar,"◀",func(): select_frame(model.selected-1)); frame_spin=UI.spin(frame_bar,"프레임",0,0); frame_spin.value_changed.connect(func(value): if not refreshing: select_frame(int(value)))
	UI.button(frame_bar,"▶",func(): select_frame(model.selected+1))
	UI.button(frame_bar,"빈 프레임 +",func(): add_frame(false)); UI.button(frame_bar,"이미지 복제",func(): add_frame(true))
	UI.button(frame_bar,"삭제",delete_frame); UI.button(frame_bar,"앞으로 이동",func(): move_frame(-1)); UI.button(frame_bar,"뒤로 이동",func(): move_frame(1))
	var frame_scroll=ScrollContainer.new(); frame_scroll.custom_minimum_size.y=92; frame_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; frames_panel.add_child(frame_scroll)
	timeline=HBoxContainer.new(); frame_scroll.add_child(timeline)
	status=UI.label(outer,"준비"); status.custom_minimum_size.y=24; status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
func file_dialog(title: String, mode: int, filters: PackedStringArray) -> FileDialog:
	var dialog=FileDialog.new(); dialog.title=title; dialog.file_mode=mode; dialog.access=FileDialog.ACCESS_FILESYSTEM; dialog.filters=filters; dialog.use_native_dialog=false; add_child(dialog); return dialog
func build_dialogs():
	open_dialog=file_dialog("PAPNG · APNG · PNG 열기",FileDialog.FILE_MODE_OPEN_FILE,["*.papng,*.apng,*.png ; 이미지 애니메이션"]); open_dialog.file_selected.connect(request_open)
	save_dialog=file_dialog("PAPNG 저장",FileDialog.FILE_MODE_SAVE_FILE,["*.papng ; PAPNG"]); save_dialog.file_selected.connect(save_to)
	import_file_dialog=file_dialog("프레임 이미지 가져오기",FileDialog.FILE_MODE_OPEN_FILE,["*."+",*.".join(Importer.NATIVE+Importer.EXTRA)+" ; 이미지 파일","* ; 모든 파일"]); import_file_dialog.file_selected.connect(import_path)
	background_file_dialog=file_dialog("편집 배경 이미지 열기",FileDialog.FILE_MODE_OPEN_FILE,import_file_dialog.filters); background_file_dialog.file_selected.connect(load_background)
	export_dialog=file_dialog("현재 합성 프레임 PNG 내보내기",FileDialog.FILE_MODE_SAVE_FILE,["*.png ; PNG"]); export_dialog.file_selected.connect(export_png)
	accessory_dialog=file_dialog("소켓에 연결할 부속 이미지",FileDialog.FILE_MODE_OPEN_FILE,["*.papng,*.apng,*.png ; 이미지 애니메이션"]); accessory_dialog.file_selected.connect(load_accessory)
	import_dialog=ImportDialog.new(); add_child(import_dialog); import_dialog.copied.connect(func(data): clipboard=data; stop_playback(); canvas.start_paste(clipboard))
	raw_dialog=ConfirmationDialog.new(); raw_dialog.title="JSON5 메타데이터"; raw_dialog.ok_button_text="적용"; add_child(raw_dialog)
	raw_text=CodeEdit.new(); raw_text.custom_minimum_size=Vector2(650,450); raw_text.gutters_draw_line_numbers=true; raw_text.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY; raw_dialog.add_child(raw_text); raw_dialog.confirmed.connect(apply_raw)
	new_dialog=ConfirmationDialog.new(); new_dialog.title="새 픽셀 이미지"; add_child(new_dialog); var box=VBoxContainer.new(); new_dialog.add_child(box)
	new_width=UI.spin(box,"너비",1,8192); new_height=UI.spin(box,"높이",1,8192); new_width.value=32; new_height.value=32
	new_dialog.confirmed.connect(func():
		var w=int(new_width.value); var h=int(new_height.value)
		if w*h*6>Model.MAX_BYTES: notify("캔버스가 256 MiB 편집 예산을 초과합니다."); return
		var doc=Model.new(); doc.new_document(w,h); bind_model(doc); canvas.fit())
	discard_dialog=ConfirmationDialog.new(); discard_dialog.title="저장되지 않은 변경"; discard_dialog.dialog_text="현재 변경사항을 저장하지 않고 계속할까요?"; discard_dialog.ok_button_text="저장하지 않고 계속"; discard_dialog.cancel_button_text="편집으로 돌아가기"; add_child(discard_dialog)
	discard_dialog.confirmed.connect(func(): if pending_action.is_valid(): pending_action.call(); pending_action=Callable())
	notice_dialog=AcceptDialog.new(); notice_dialog.title="PAPNG Editor"; add_child(notice_dialog)
	busy_dialog=AcceptDialog.new(); busy_dialog.title="처리 중"; busy_dialog.get_ok_button().hide(); busy_dialog.unresizable=true; add_child(busy_dialog)
	var busy_box=VBoxContainer.new(); busy_dialog.add_child(busy_box); busy_label=UI.label(busy_box,""); busy_label.custom_minimum_size=Vector2(400,65); busy_cancel=UI.button(busy_box,"취소",cancel_job)
	busy_dialog.close_requested.connect(func(): cancel_job(); busy_dialog.popup_centered())
func bind_model(next):
	stop_playback(); model=next; model.changed.connect(func(): needs_refresh=true; preview_dirty=true; refs.clear())
	canvas.model=model; canvas.clear_reference(); background_controls.sync(); canvas.selection=Rect2i(); canvas.cancel_paste(); hues.clear(); refs.clear(); canvas.hue_offsets=hues
	clear_accessory(); preview_dirty=true; refresh_all()
	if not model.warnings.is_empty(): notify("불러오기 경고: "+"; ".join(model.warnings))
func refresh_all():
	refreshing=true; needs_refresh=false; preview_dirty=true; canvas.refresh(); inspector.sync()
	frame_spin.max_value=model.frames.size()-1; frame_spin.set_value_no_signal(model.selected)
	frame_info.text="원본 프레임 %d / %d   ·   %d × %d px   ·   %s" % [model.selected,model.frames.size()-1,model.width,model.height,tool_names[canvas.tool]]
	title_info.text=("● " if model.dirty() else "")+(model.path.get_file() if not model.path.is_empty() else "새 이미지")
	get_window().title=title_info.text+" — PAPNG Editor"
	for node in timeline.get_children(): timeline.remove_child(node); node.queue_free()
	var first=maxi(0,model.selected-12); var last=mini(model.frames.size(),first+25)
	for i in range(first,last):
		var f=model.frames[i]; var image=model.source_image(i); image.resize(36,36,Image.INTERPOLATE_NEAREST)
		var button=UI.button(timeline,"%d\n%d/%d" % [i,f.num,f.den],func(): select_frame(i),"원본 프레임 %d · %s" % [i,"순차" if f.control.is_empty() else "확장 제어 "+str(f.control.type)])
		button.icon=ImageTexture.create_from_image(image); button.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER; button.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP; button.toggle_mode=true; button.button_pressed=i==model.selected; button.custom_minimum_size=Vector2(72,76); button.add_theme_font_size_override("font_size",12)
	refreshing=false
func cursor_info(point: Vector2i, data: Dictionary):
	if data.is_empty(): pixel_info.text="커서: (%d, %d) · 원본 프레임 밖\nRGBA: —\nHSV: —\n마스크: —" % [point.x,point.y]; return
	var p=data.rgba; var color=Color8(p[0],p[1],p[2],p[3])
	pixel_info.text="커서: (%d, %d)\nRGBA: %d, %d, %d, %d\nHSV: %.1f° · %.1f%% · %.1f%%\n마스크: %s" % [point.x,point.y,p[0],p[1],p[2],p[3],color.h*360,color.s*100,color.v*100,"없음" if data.mask<0 else str(data.mask)]
func edit(label: String, action: Callable):
	if busy(): return
	stop_playback(); canvas.stop_gesture(); model.begin(label); action_error=""; action.call()
	if action_error.is_empty(): action_error=model.validate()
	if not action_error.is_empty(): model.cancel(); notify(action_error)
	else: model.commit()
	refresh_all()
func select_tool(key: String):
	stop_playback(); canvas.stop_gesture(); canvas.tool=key; tool_buttons[key].button_pressed=true; canvas.grab_focus()
	if key=="mask": inspector.current_tab=1
	elif key=="socket": inspector.current_tab=2
	frame_info.text="원본 프레임 %d · %d × %d px · %s" % [model.selected,model.width,model.height,tool_names[key]]
func select_frame(index: int):
	if index<0 or index>=model.frames.size() or busy(): return
	stop_playback(); canvas.stop_gesture(); canvas.cancel_paste(); model.selected=index; refs.clear(); canvas.selection=Rect2i(); refresh_all()
func undo():
	if busy(): return
	stop_playback(); canvas.stop_gesture(); canvas.cancel_paste(); model.undo(); refresh_all()
func redo():
	if busy(): return
	stop_playback(); canvas.stop_gesture(); canvas.cancel_paste(); model.redo(); refresh_all()
func copy(cut: bool):
	if busy(): return
	stop_playback(); clipboard=canvas.copy_selection(cut); notify("앱 클립보드에 복사했습니다. Ctrl+V로 배치할 수 있습니다.")
func paste():
	if clipboard.is_empty(): notify("앱 클립보드가 비어 있습니다. 이미지 가져오기 또는 Ctrl+C를 사용하세요."); return
	stop_playback(); canvas.start_paste(clipboard)
func external_paste():
	if not DisplayServer.clipboard_has_image(): notify("시스템 클립보드에 이미지가 없습니다."); return
	var image=DisplayServer.clipboard_get_image()
	if image==null or image.is_empty(): notify("클립보드 이미지를 읽을 수 없습니다."); return
	image.convert(Image.FORMAT_RGBA8); import_dialog.open_image(image,"시스템 클립보드")
func add_frame(duplicate: bool):
	edit("이미지 프레임 복제" if duplicate else "빈 프레임 추가",func():
		var order=range(model.frames.size()); var at=model.selected+1; order.insert(at,-1)
		var frame=model.frames[model.selected].duplicate(true) if duplicate else model.blank(model.width,model.height); frame.control={}
		action_error=FrameEdit.remap(model,order,{at:frame})
		if action_error.is_empty(): model.selected=at)
func delete_frame():
	if model.frames.size()==1: notify("최소 한 프레임이 필요합니다."); return
	edit("프레임 삭제",func(): var order=range(model.frames.size()); order.remove_at(model.selected); action_error=FrameEdit.remap(model,order))
func move_frame(delta: int):
	var target=model.selected+delta
	if target<0 or target>=model.frames.size(): return
	edit("프레임 순서",func(): var order=range(model.frames.size()); var old=order[model.selected]; order[model.selected]=order[target]; order[target]=old; action_error=FrameEdit.remap(model,order))
func set_hue(id: int, degrees: float):
	stop_playback(); hues[id]=degrees; canvas.hue_offsets=hues; canvas.refresh(); preview_dirty=true; inspector.sync_mask()
func mask_reference(id: int) -> Color:
	if refs.has(id): return refs[id]
	var sum=Vector3.ZERO; var weight=0.0
	# The reference swatch describes the currently editable source frame.
	var f=model.frames[model.selected]
	for pos in range(0,f.mask.size(),2):
		if f.mask[pos]&0x80 and (((f.mask[pos]<<8)|f.mask[pos+1])&0x7fff)==id:
			var at=pos*2; var alpha=f.rgba[at+3]/255.0; sum+=Vector3(f.rgba[at],f.rgba[at+1],f.rgba[at+2])*alpha; weight+=alpha
	var color=Color(sum.x/(255*weight),sum.y/(255*weight),sum.z/(255*weight)) if weight>0 else Color.TRANSPARENT
	refs[id]=color; return color
func start_playback(clip: int = -1):
	if busy(): return
	canvas.stop_gesture(); canvas.cancel_paste(); player=Player.new(model.runtime()); player.offsets=hues.duplicate()
	if clip>=player.doc.clips.size(): clip=-1
	player.restart(clip); canvas.playing=true; play_button.text="Ⅱ 정지"; preview_frame=-1
	if accessory_player!=null: accessory_player.restart()
func stop_playback():
	if canvas==null: return
	canvas.playing=false; canvas.playback_texture=null; canvas.playback_marks=null; canvas.playback_index=-1; canvas.queue_redraw(); preview_dirty=true
	if play_button!=null: play_button.text="▶ 재생"
	if frame_info!=null: frame_info.text="원본 프레임 %d / %d · %d × %d px · %s" % [model.selected,model.frames.size()-1,model.width,model.height,tool_names[canvas.tool]]
func update_preview():
	if not preview_dirty or canvas.playing: return
	player=Player.new(model.runtime()); player.offsets=hues.duplicate(); player.seek_canvas(model.selected)
	if not player.state.is_empty(): mini.set_image(Image.create_from_data(model.width,model.height,false,Image.FORMAT_RGBA8,player.state.pixels))
	preview_dirty=false
func _process(delta):
	if worker!=null:
		busy_label.text=("불러오는 중" if job_kind=="open" else "이미지를 준비하는 중" if job_kind in ["import","reference"] else "저장하는 중" if job_kind=="save" else "부속을 읽는 중")+" · %.1f초\n처리가 끝나면 자동으로 닫힙니다." % ((Time.get_ticks_msec()-job_started)/1000.0)
		if not worker.is_alive(): finish_job()
	if needs_refresh and not canvas.dragging: refresh_all()
	elif needs_refresh: canvas.refresh(); preview_dirty=true; needs_refresh=false
	if busy(): return
	if canvas.playing and player!=null:
		player.tick(delta)
		if player.changed:
			if not player.presented.is_empty():
				var image=Image.create_from_data(model.width,model.height,false,Image.FORMAT_RGBA8,player.presented)
				canvas.playback_texture=ImageTexture.create_from_image(image); canvas.playback_index=player.visible; mini.set_image(image)
				canvas.playback_marks=ImageTexture.create_from_image(Image.create_from_data(model.width,model.height,false,Image.FORMAT_RGBA8,player.presented_marks))
				frame_info.text="재생 프레임 %d / %d · %d × %d px" % [player.visible,model.frames.size()-1,model.width,model.height]
			player.changed=false; canvas.queue_redraw()
		if player.ended: stop_playback(); notify("재생을 마쳤습니다.")
	else: update_preview()
	if accessory_player!=null:
		if canvas.playing: accessory_player.tick(delta)
		if accessory_player.changed and not accessory_player.presented.is_empty():
			canvas.accessory_texture=ImageTexture.create_from_image(Image.create_from_data(accessory.width,accessory.height,false,Image.FORMAT_RGBA8,accessory_player.presented)); accessory_player.changed=false; canvas.queue_redraw()
	canvas.update_origin(); mini.viewport_rect=Rect2(-canvas.origin/canvas.zoom,canvas.size/canvas.zoom); mini.queue_redraw()
func place_socket(point: Vector2i):
	inspector.sx.value=point.x+0.5; inspector.sy.value=point.y+0.5; inspector.apply_socket()
func choose_accessory():
	if model.runtime().sockets_at(model.selected).is_empty(): notify("소켓을 먼저 추가하세요."); return
	accessory_dialog.popup_centered_ratio(0.8)
func clear_accessory():
	accessory=null; accessory_player=null
	if canvas!=null: canvas.accessory_texture=null; canvas.queue_redraw()
func guard(action: Callable):
	if busy(): return
	canvas.stop_gesture()
	if model.dirty(): pending_action=action; discard_dialog.popup_centered()
	else: action.call()
func request_new(): guard(func(): new_dialog.popup_centered())
func request_open(path: String): guard(func(): start_job("open",path))
func import_path(path: String): start_job("import",path)
func load_background(path: String):
	if not path.begins_with("content://") and not FileAccess.file_exists(path): notify("참고 이미지 파일을 찾을 수 없습니다."); return
	start_job("reference",path)
func show_background_settings():
	background_toggle.button_pressed=true
	background_scroll.ensure_control_visible.call_deferred(background_controls)
func choose_background():
	if busy(): return
	canvas.stop_gesture(); background_file_dialog.popup_centered_ratio(0.8)
func load_accessory(path: String): start_job("accessory",path)
func save():
	if busy(): return
	canvas.stop_gesture()
	if model.path.get_extension().to_lower()!="papng": save_as()
	else: save_to(model.path)
func save_as():
	save_dialog.current_file=(model.path.get_file().get_basename() if not model.path.is_empty() else "untitled")+".papng"; save_dialog.popup_centered_ratio(0.75)
func save_to(path: String):
	if path.get_extension().to_lower()!="papng": path+=".papng"
	canvas.stop_gesture(); start_job("save",path)
func export_png(path: String):
	if path.get_extension().to_lower()!="png": path+=".png"
	update_preview(); var image=mini.texture.get_image()
	if image.save_png(path)!=OK: notify("PNG 내보내기에 실패했습니다.")
	else: notify("현재 합성 결과를 PNG로 내보냈습니다: "+path)
func busy() -> bool: return worker!=null
func start_job(kind: String, path: String):
	if busy(): return
	stop_playback(); canvas.stop_gesture(); job_kind=kind; job_started=Time.get_ticks_msec(); job_cancelled=false; job_result={}; job_importer=null
	worker=Thread.new(); busy_dialog.title="저장" if kind=="save" else "불러오기"; busy_cancel.visible=kind!="save"; busy_dialog.popup_centered()
	var snapshot=model.state() if kind=="save" else {}; var extras=model.ancillary.duplicate(true) if kind=="save" else []
	var result=worker.start(func():
		if kind in ["import","reference"]:
			var decoder=make_importer(); decoder.converter=converter; job_importer=decoder
			var image=decoder.load_image(path); job_result={"ok":image!=null,"image":image,"error":decoder.error,"path":path,"decoder":decoder.decoder}
		elif kind=="save":
			var copy=Model.new(); copy.restore(snapshot); copy.ancillary=extras
			var ok=write_document(copy,path); job_result={"ok":ok,"error":copy.error,"path":path,"revision":snapshot.revision}
		elif kind=="open":
			var doc=Model.new(); var ok=doc.load_file(path,func(): return job_cancelled); job_result={"ok":ok,"model":doc,"error":doc.error,"path":path}
		else:
			var doc=Doc.new(); var ok=doc.load_file(path,func(): return job_cancelled); job_result={"ok":ok,"doc":doc,"error":doc.error,"path":path})
	if result!=OK: worker=null; busy_dialog.hide(); notify("작업 스레드를 시작하지 못했습니다.")
func cancel_job():
	if job_kind=="save": return
	job_cancelled=true
	if job_importer!=null: job_importer.cancelled=true
	busy_label.text="작업을 취소하고 있습니다…"
func finish_job():
	worker.wait_to_finish(); worker=null; busy_dialog.hide()
	var result=job_result
	if job_cancelled: notify("불러오기를 취소했습니다."); return
	if not result.get("ok",false): notify(result.get("error","작업 실패")); return
	match job_kind:
		"open": bind_model(result.model); canvas.fit(); notify("열었습니다: "+result.path+(" · 경고 "+str(model.warnings.size())+"개" if not model.warnings.is_empty() else ""))
		"import": import_dialog.open_image(result.image,result.path.get_file()+" · "+result.decoder)
		"reference":
			canvas.set_reference(result.image); job_result.erase("image"); background_controls.sync(); notify("참고 이미지를 배경에 놓았습니다. 배경 설정에서 위치·배율·불투명도를 조절하세요.")
		"save": model.path=result.path; model.saved_revision=result.revision; refresh_all(); notify("저장했습니다: "+result.path)
		"accessory":
			accessory=result.doc; accessory.cancel=Callable(); accessory_player=Player.new(accessory); accessory_player.restart(); canvas.accessory_pivot=Vector2(accessory.hints.get("pivot",[0,0])[0],accessory.hints.get("pivot",[0,0])[1]); notify("선택한 소켓에 부속을 연결했습니다. 연결은 미리보기에만 사용됩니다.")
func show_metadata(): raw_mode="metadata"; raw_dialog.title="JSON5 메타데이터 · 주석과 사용자 필드"; raw_text.text=model.metadata_text; raw_dialog.popup_centered_ratio(0.8)
func show_groups():
	raw_mode="groups"; raw_dialog.title="마스크 그룹 · id / name / palette_indices"; raw_text.text=Metadata.encode(model.metadata().get("mask_groups",[])); raw_dialog.popup_centered_ratio(0.8)
func show_distributions():
	raw_mode="distributions"; raw_dialog.title="추가 분포 · 0번 균등분포는 고정"; raw_text.text="// 배열의 첫 항목 = 분포 1. 최대 255개.\n// kind: 0 균등, 1 중앙 우선, 2 작은 값 우선, 3 큰 값 우선, 4 가중치 값\n// 예: {kind: 4, items: [{value: 100, weight: 2}, {value: 300, weight: 1}]}\n"+Metadata.encode(model.distributions.slice(1)); raw_dialog.popup_centered_ratio(0.8)
func apply_raw():
	var parser=Parser.new(); var data=parser.parse(raw_text.text)
	if not parser.error.is_empty(): notify(parser.error); raw_dialog.popup_centered_ratio(0.8); return
	edit("메타데이터 편집",func():
		if raw_mode=="metadata": model.metadata_text=raw_text.text; model.touch()
		elif raw_mode=="groups": model.put_metadata("mask_groups",data)
		else:
			if not data is Array or data.size()>255: action_error="추가 분포는 0~255개의 배열이어야 합니다."; return
			var defs=[{"kind":0,"valid":true,"items":[]}]
			for d in data:
				if not d is Dictionary or not d.has("kind") or not d.kind is float and not d.kind is int or d.kind!=int(d.kind) or not d.get("items",[]) is Array: action_error="분포에는 정수 kind와 items 배열이 필요합니다."; return
				var items=[]
				for item in d.get("items",[]):
					if not item is Dictionary or not item.get("value") is float and not item.get("value") is int or not item.get("weight") is float and not item.get("weight") is int: action_error="각 항목에는 정수 value와 weight가 필요합니다."; return
					if not is_finite(item.value) or not is_finite(item.weight) or item.value!=int(item.value) or item.weight!=int(item.weight): action_error="value와 weight는 유한한 정수여야 합니다."; return
					items.append({"value":int(item.value),"weight":int(item.weight)})
				defs.append({"kind":int(d.kind),"valid":true,"items":items})
			model.distributions=defs; model.touch())
	if not action_error.is_empty(): raw_dialog.popup_centered_ratio(0.8)
func show_settings():
	var dialog=ConfirmationDialog.new(); dialog.title="이미지 가져오기 설정"; add_child(dialog); var box=VBoxContainer.new(); dialog.add_child(box)
	UI.label(box,"Godot에서 읽지 못하는 형식에는 ImageMagick을 사용합니다.\n자동 검색되지 않으면 magick 실행 파일의 전체 경로를 지정하세요.\n변환기는 첫 이미지/합성 레이어를 읽고 최대 4096 × 4096으로 맞춥니다.")
	var value=UI.entry(box,"ImageMagick 경로 (비어 있으면 PATH에서 검색)"); value.text=converter; value.custom_minimum_size.x=600
	dialog.confirmed.connect(func(): converter=value.text.strip_edges(); var cfg=ConfigFile.new(); cfg.set_value("import","converter",converter); cfg.save("user://editor.cfg"); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered()
func load_settings():
	var cfg=ConfigFile.new()
	if cfg.load("user://editor.cfg")==OK: converter=cfg.get_value("import","converter","")
func show_help():
	notice_dialog.dialog_text="PAPNG Editor · 픽셀과 애니메이션\n\nB 연필 · E 지우개 · G 채우기 · I 스포이트 · R 선택\nL 직선 · U 사각형 · M 마스크 (Shift로 해제) · K 소켓\n마우스 휠: 정수 배율 · 가운데 버튼 / Space+드래그: 이동\nF 화면 맞춤 · 1 실제 크기 · ← / → 프레임 이동\nCtrl+Space 재생 · Ctrl+Z / Y 실행 취소 / 다시 실행\nCtrl+C / X / V 앱 클립보드 · Ctrl+Shift+V 시스템 이미지 가져오기\nEnter 붙이기 확정 · Esc 취소 · Delete 선택 영역 지우기\n\n가운데 화면은 원본 프레임을 편집합니다. 미니맵과 재생은 합성 결과입니다.\n부분 프레임 바깥을 편집하려면 프레임 탭에서 원본 영역을 넓히세요.\n이미지 복제는 픽셀·마스크·시간을 복사하며 확장 이동 제어는 복사하지 않습니다.\n색상각과 부속 연결은 미리보기 설정이며 저장되는 원본색은 변하지 않습니다."
	notice_dialog.popup_centered()
func notify(text: String):
	if status!=null: status.text=text; status.tooltip_text=text
func _notification(what):
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if busy(): notify("현재 파일 작업을 끝내거나 취소한 뒤 종료하세요."); return
		guard(func(): get_tree().quit())
func modal_open() -> bool:
	for child in get_children():
		if child is Window and child.visible: return true
	return false
func _unhandled_key_input(event):
	if not event is InputEventKey or not event.pressed or event.echo or busy() or modal_open(): return
	var focus=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	var key=event.keycode
	if event.ctrl_pressed or event.meta_pressed:
		match key:
			KEY_N: request_new()
			KEY_O: open_dialog.popup_centered_ratio(0.8)
			KEY_S: save_as() if event.shift_pressed else save()
			KEY_I: import_file_dialog.popup_centered_ratio(0.8)
			KEY_Z: redo() if event.shift_pressed else undo()
			KEY_Y: redo()
			KEY_C: copy(false)
			KEY_X: copy(true)
			KEY_V: external_paste() if event.shift_pressed else paste()
			KEY_SPACE: stop_playback() if canvas.playing else start_playback()
			KEY_A: canvas.selection=model.frame_rect(); canvas.queue_redraw()
			_: return
	else:
		match key:
			KEY_B: select_tool("pencil")
			KEY_E: select_tool("erase")
			KEY_G: select_tool("fill")
			KEY_I: select_tool("pick")
			KEY_R: select_tool("select")
			KEY_L: select_tool("line")
			KEY_U: select_tool("rect")
			KEY_M: select_tool("mask")
			KEY_K: select_tool("socket")
			KEY_F: canvas.fit()
			KEY_1: canvas.set_zoom(1)
			KEY_EQUAL,KEY_PLUS: canvas.set_zoom(canvas.zoom+1)
			KEY_MINUS: canvas.set_zoom(canvas.zoom-1)
			KEY_LEFT: select_frame(model.selected-1)
			KEY_RIGHT: select_frame(model.selected+1)
			KEY_ENTER,KEY_KP_ENTER: stop_playback(); canvas.apply_paste()
			KEY_ESCAPE: canvas.cancel_paste(); canvas.stop_gesture(); canvas.selection=Rect2i(); canvas.queue_redraw(); stop_playback()
			KEY_DELETE: stop_playback(); canvas.clear_selection()
			_: return
	get_viewport().set_input_as_handled()
