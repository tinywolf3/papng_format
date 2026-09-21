extends "res://editor.gd"
## Android presentation; document, undo, animation and extension editing are shared.
const TouchCanvas=preload("res://mobile/touch_canvas.gd")
const MobileImporter=preload("res://mobile/import_image.gd")
var outer: VBoxContainer
var safe_area: MarginContainer
var sheet: Control
var sheet_panel: PanelContainer
var sheet_content: VBoxContainer
var sheet_title: Label
var sheets: Dictionary={}
var sheet_page=""
var extension_choice: OptionButton
var frame_scroll: ScrollContainer
var paste_bar: HBoxContainer
var context_bar: HBoxContainer
var frames_button: Button
var pan_button: Button
var intent_id=0
var intent_elapsed=0.0
var display_path=""
var save_uri=""
var recovery_pending=false
var last_recovery=-1
var recovery_clock=0.0
var mobile_ready=false
var distribution_dialog
var keyboard_height=0
var unobscured_size=Vector2.ZERO
var recovery_worker: Thread
var recovery_result=false
var recovery_revision=-1
var recovery_generation=0
var document_generation=0
func configure_window():
	get_window().min_size=Vector2i(320,320)
	get_window().content_scale_size=Vector2i.ZERO
	if OS.get_name()=="Android":
		get_tree().quit_on_go_back=false
		get_window().content_scale_factor=maxf(1,float(mini(get_window().size.x,get_window().size.y))/430.0)
	else: get_window().size=Vector2i(430,860)
func _ready():
	super._ready()
	theme.default_font_size=14
	get_viewport().size_changed.connect(layout_mobile)
	adapt_controls(self); layout_mobile(); mobile_ready=true
	if not FileAccess.file_exists("user://recovery.papng") and FileAccess.file_exists("user://recovery-next.papng"):
		DirAccess.rename_absolute("user://recovery-next.papng","user://recovery.papng")
	if FileAccess.file_exists("user://recovery.papng"):
		var restore=ConfirmationDialog.new(); restore.title="작업 복구"; restore.dialog_text="이전에 저장되지 않은 작업을 이어서 편집할까요?"; restore.ok_button_text="복구"; restore.cancel_button_text="새로 시작"; add_child(restore)
		restore.confirmed.connect(func(): recovery_pending=true; start_job("open","user://recovery.papng"); restore.queue_free())
		restore.canceled.connect(func(): DirAccess.remove_absolute("user://recovery.papng"); restore.queue_free(); poll_intent())
		adapt_controls(restore); restore.popup_centered_clamped(Vector2i(340,180),0.9)
	else: poll_intent.call_deferred()
func build_ui():
	safe_area=MarginContainer.new(); safe_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(safe_area)
	outer=VBoxContainer.new(); outer.add_theme_constant_override("separation",3); safe_area.add_child(outer)
	var top=UI.row(outer)
	Icons.button(top,"menu","파일과 편집",func(): show_sheet("file"))
	title_info=UI.label(top,"새 이미지"); title_info.size_flags_horizontal=Control.SIZE_EXPAND_FILL; title_info.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; title_info.custom_minimum_size.x=30
	Icons.button(top,"undo","실행 취소",undo); Icons.button(top,"redo","다시 실행",redo)
	Icons.button(top,"save","PAPNG 저장",save)
	var info=UI.row(outer)
	var mini_scroll=ScrollContainer.new(); mini_scroll.custom_minimum_size=Vector2(76,72); mini_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; info.add_child(mini_scroll)
	mini=Mini.new(); mini_scroll.add_child(mini); mini.centered.connect(func(point): canvas.pan=(Vector2(model.width,model.height)/2-point)*canvas.zoom; canvas.queue_redraw())
	var details=VBoxContainer.new(); details.size_flags_horizontal=Control.SIZE_EXPAND_FILL; info.add_child(details)
	frame_info=UI.label(details,""); frame_info.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; frame_info.add_theme_font_size_override("font_size",12)
	pixel_info=UI.label(details,"픽셀을 터치하면 색상과 마스크를 표시합니다."); pixel_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; pixel_info.add_theme_font_size_override("font_size",12)
	canvas=TouchCanvas.new(); canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL; canvas.custom_minimum_size=Vector2(200,96); outer.add_child(canvas)
	canvas.zoom_changed.connect(func(value): zoom_spin.set_value_no_signal(value)); canvas.cursor_changed.connect(cursor_info)
	canvas.picked.connect(func(value): color_button.color=value; canvas.color=value; select_tool("pencil"))
	canvas.message.connect(notify); canvas.socket_placed.connect(place_socket)
	paste_bar=UI.row(outer); paste_bar.hide()
	UI.button(paste_bar,"✓ 적용",func(): canvas.apply_paste()); UI.button(paste_bar,"취소",func(): canvas.cancel_paste())
	UI.check(paste_bar,"투명도 교체").toggled.connect(func(on): canvas.replace_paste=on)
	var playback=UI.row(outer)
	play_button=UI.button(playback,"▶ 재생",func(): stop_playback() if canvas.playing else start_playback()); play_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	UI.button(playback,"‹",func(): select_frame(model.selected-1))
	frame_spin=UI.spin(playback,"",0,0); frame_spin.custom_minimum_size.x=76; frame_spin.value_changed.connect(func(value): if not refreshing: select_frame(int(value)))
	UI.button(playback,"›",func(): select_frame(model.selected+1))
	frames_button=Icons.button(playback,"frames","프레임 목록",func(): frame_scroll.visible=not frame_scroll.visible)
	frame_scroll=ScrollContainer.new(); frame_scroll.custom_minimum_size.y=84; frame_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; outer.add_child(frame_scroll)
	timeline=HBoxContainer.new(); frame_scroll.add_child(timeline)
	context_bar=UI.row(outer)
	color_button=ColorPickerButton.new(); color_button.color=Color("ebbb71"); color_button.custom_minimum_size=Vector2(54,48); context_bar.add_child(color_button)
	color_button.color_changed.connect(func(value): canvas.color=value)
	var brush=UI.spin(context_bar,"",1,64); brush.custom_minimum_size.x=70; brush.suffix="px"; brush.value_changed.connect(func(value): canvas.brush=int(value))
	pan_button=Icons.button(context_bar,"pan","한 손가락 화면 이동",func(): canvas.move_mode=pan_button.button_pressed); pan_button.toggle_mode=true
	Icons.button(context_bar,"fit","화면 맞춤",func(): canvas.fit())
	var extension=UI.button(context_bar,"속성",func(): show_sheet("extensions")); extension.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	Icons.button(context_bar,"settings","보기 설정",func(): show_sheet("view"))
	var tool_scroll=ScrollContainer.new(); tool_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; tool_scroll.custom_minimum_size.y=62; outer.add_child(tool_scroll)
	var tools=HBoxContainer.new(); tool_scroll.add_child(tools); var group=ButtonGroup.new()
	for key in tool_names:
		var button=Icons.button(tools,key,tool_names[key].split("  ")[0],func(): select_tool(key),Icons.SHORTCUTS[key]); button.toggle_mode=true; button.button_group=group; tool_buttons[key]=button
	tool_buttons.pencil.button_pressed=true
	status=UI.label(outer,"한 손가락: 그리기 · 두 손가락: 확대 / 이동"); status.custom_minimum_size.y=24; status.add_theme_font_size_override("font_size",12); status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	build_sheet()
func build_sheet():
	sheet=Control.new(); sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); sheet.mouse_filter=Control.MOUSE_FILTER_STOP; add_child(sheet)
	var shade=ColorRect.new(); shade.color=Color(0,0,0,0.55); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); sheet.add_child(shade)
	sheet_panel=PanelContainer.new(); sheet.add_child(sheet_panel); var column=VBoxContainer.new(); sheet_panel.add_child(column)
	var heading=UI.row(column); sheet_title=UI.label(heading,""); sheet_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	UI.button(heading,"닫기",hide_sheet)
	sheet_content=VBoxContainer.new(); sheet_content.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(sheet_content)
	var files=sheet_scroll("file")
	for item in [["새 이미지",request_new],["PAPNG · APNG · PNG 열기",func(): open_dialog.popup_centered_ratio(0.9)],["다른 이름으로 저장",save_as],["이미지 가져오기 / 오려내기",func(): import_file_dialog.popup_centered_ratio(0.9)],["합성 프레임 PNG 내보내기",func(): export_dialog.current_file="frame.png"; export_dialog.popup_centered_ratio(0.9)]]:
		UI.button(files,item[0],func(): hide_sheet(); item[1].call())
	var selection=UI.row(files)
	for item in [["copy","복사",func(): copy(false)],["cut","잘라내기",func(): copy(true)],["paste","붙여넣기",paste],["clear","선택 해제",func(): canvas.selection=Rect2i(); canvas.queue_redraw()]]:
		Icons.button(selection,item[0],item[1],func(): hide_sheet(); item[2].call())
	UI.button(files,"선택 영역 지우기",func(): hide_sheet(); stop_playback(); canvas.clear_selection())
	UI.label(files,"프레임")
	for item in [["빈 프레임 추가",func(): add_frame(false)],["현재 이미지 복제",func(): add_frame(true)],["현재 프레임 삭제",delete_frame],["앞으로 이동",func(): move_frame(-1)],["뒤로 이동",func(): move_frame(1)]]:
		UI.button(files,item[0],func(): hide_sheet(); item[1].call())
	UI.button(files,"사용 방법",func(): hide_sheet(); show_help())
	var extensions=VBoxContainer.new(); extensions.size_flags_vertical=Control.SIZE_EXPAND_FILL; sheet_content.add_child(extensions); sheets.extensions=extensions
	extension_choice=UI.options(extensions,"",["프레임 · 지연 / 제어","마스크 · 이름 / 색상","소켓 · 위치 / 회전","출력 힌트 · 피벗","애니메이션 클립"])
	inspector=Inspector.new(); inspector.host=self; inspector.tabs_visible=false; inspector.size_flags_vertical=Control.SIZE_EXPAND_FILL; extensions.add_child(inspector)
	extension_choice.item_selected.connect(func(index): inspector.current_tab=index)
	var view=sheet_scroll("view")
	zoom_spin=UI.spin(view,"정수 배율",1,128); zoom_spin.suffix="×"; zoom_spin.value_changed.connect(func(value): canvas.set_zoom(int(value)))
	for setting in [["격자","show_grid",true],["픽셀 중앙 십자선","show_cross",true],["마스크 영역 강조","show_mask",false],["힌트 / 피벗","show_hints",true],["소켓 위치 / 이름","show_sockets",true],["이전 합성 프레임","onion",false]]:
		var property=setting[1]; UI.check(view,setting[0],setting[2]).toggled.connect(func(on): canvas.set(property,on); canvas.refresh())
	UI.check(view,"마스크 브러시로 해제").toggled.connect(func(on): canvas.clear_mask=on)
	UI.label(view,"편집 배경")
	background_controls=BackgroundControls.new(); background_controls.host=self; view.add_child(background_controls)
	UI.button(view,"1:1 실제 크기",func(): canvas.set_zoom(1); hide_sheet())
	UI.button(view,"화면에 맞춤",func(): canvas.fit(); hide_sheet())
	sheet.hide()
func sheet_scroll(key: String) -> VBoxContainer:
	var scroll=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; sheet_content.add_child(scroll); sheets[key]=scroll
	var box=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(box); return box
func show_sheet(key: String):
	canvas.stop_gesture(); sheet_page=key
	for name in sheets: sheets[name].visible=name==key
	sheet_title.text={"file":"파일 · 편집","extensions":"PAPNG 속성","view":"보기"}[key]
	if key=="extensions": extension_choice.select(inspector.current_tab)
	sheet.show(); canvas.enabled=false; layout_mobile()
func hide_sheet(): sheet.hide(); canvas.enabled=true
func build_dialogs():
	super.build_dialogs()
	distribution_dialog=preload("res://mobile/distributions.gd").new(); distribution_dialog.host=self; add_child(distribution_dialog)
	remove_child(import_dialog); import_dialog.queue_free()
	import_dialog=preload("res://mobile/import_dialog.gd").new(); add_child(import_dialog)
	import_dialog.copied.connect(func(data): clipboard=data; stop_playback(); canvas.start_paste(clipboard))
	raw_text.custom_minimum_size=Vector2(250,120); raw_text.add_theme_font_size_override("font_size",14)
	busy_label.custom_minimum_size=Vector2(240,70); busy_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	for dialog in [raw_dialog,new_dialog,discard_dialog,notice_dialog,busy_dialog,import_dialog,distribution_dialog]:
		dialog.visibility_changed.connect(func(): if dialog.visible: fit_dialog.call_deferred(dialog))
func file_dialog(title: String, mode: int, filters: PackedStringArray) -> FileDialog:
	var dialog=super.file_dialog(title,mode,filters)
	dialog.use_native_dialog=OS.get_name()=="Android"
	if mode==FileDialog.FILE_MODE_OPEN_FILE: dialog.add_filter("*","모든 파일")
	return dialog
func adapt_controls(node: Node):
	if node is BaseButton: node.custom_minimum_size.y=maxf(node.custom_minimum_size.y,48)
	if node is Button:
		node.clip_text=true
		if node.icon==null and not node.text.is_empty(): node.custom_minimum_size.x=maxf(node.custom_minimum_size.x,minf(300,node.get_theme_default_font().get_string_size(node.text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+(52 if node is CheckBox else 28)))
	if node is LineEdit: node.custom_minimum_size.y=maxf(node.custom_minimum_size.y,44)
	if node is Slider: node.custom_minimum_size.y=48
	if node is Label and node not in [title_info,frame_info,status]:
		node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		if node.get_parent() is HBoxContainer: node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for child in node.get_children(): adapt_controls(child)
func layout_mobile():
	if safe_area==null: return
	var viewport=get_viewport_rect().size
	var margins=[4,4,4,4]
	if OS.get_name()=="Android":
		var safe=DisplayServer.get_display_safe_area(); var factor=get_window().content_scale_factor
		margins=[maxi(4,ceili(safe.position.x/factor)),maxi(4,ceili((get_window().size.x-safe.end.x)/factor)),maxi(4,ceili(safe.position.y/factor)),maxi(4,ceili((get_window().size.y-safe.end.y)/factor))]
	for i in 4: safe_area.add_theme_constant_override("margin_"+["left","right","top","bottom"][i],margins[i])
	var available=Vector2(viewport.x-margins[0]-margins[1],viewport.y-margins[2]-margins[3]-keyboard_height)
	sheet_panel.position=Vector2(margins[0]+4,margins[2]+4); sheet_panel.size=available-Vector2(8,8)
	if available.y<550: frame_scroll.hide()
	for child in get_children():
		if child is Window and child.visible: fit_dialog(child)
func fit_dialog(dialog: Window):
	var viewport=get_viewport_rect().size-Vector2(0,keyboard_height)
	if dialog is AcceptDialog: dialog.get_ok_button().custom_minimum_size.y=48
	if dialog is ConfirmationDialog: dialog.get_cancel_button().custom_minimum_size.y=48
	if dialog==busy_dialog: dialog.size=Vector2i(minf(350,viewport.x-24),170)
	elif dialog in [raw_dialog,import_dialog,distribution_dialog]:
		dialog.wrap_controls=false; dialog.size=Vector2i(viewport-Vector2(20,80))
	else: dialog.size=Vector2i(minf(dialog.size.x,viewport.x-24),minf(dialog.size.y,viewport.y-40))
	dialog.position=Vector2i((viewport-Vector2(dialog.size))/2)
func cursor_info(point: Vector2i, data: Dictionary):
	if data.is_empty(): pixel_info.text="(%d, %d) · 원본 프레임 밖" % [point.x,point.y]; return
	var p=data.rgba; var color=Color8(p[0],p[1],p[2],p[3])
	pixel_info.text="(%d, %d)  RGBA %d · %d · %d · %d\nH %.0f°  S %.0f%%  V %.0f%% · 마스크 %s" % [point.x,point.y,p[0],p[1],p[2],p[3],color.h*360,color.s*100,color.v*100,"—" if data.mask<0 else str(data.mask)]
func select_tool(key: String):
	super.select_tool(key); canvas.move_mode=false; pan_button.button_pressed=false
	notify(tool_names[key].split("  ")[0]+(" · 속성에서 번호 선택 / 보기에서 해제 모드" if key=="mask" else " · 속성에서 소켓을 먼저 추가하세요" if key=="socket" else ""))
func refresh_all():
	super.refresh_all()
	if not display_path.is_empty(): title_info.text=("● " if model.dirty() else "")+display_path
func copy(cut: bool):
	super.copy(cut); notify("앱 안에 복사했습니다. 메뉴의 붙여넣기로 배치하세요.")
func paste():
	if clipboard.is_empty(): notify("복사하거나 이미지를 가져온 뒤 붙여넣으세요."); return
	super.paste()
func start_playback(clip: int = -1):
	if sheet!=null: hide_sheet()
	super.start_playback(clip)
func choose_background():
	hide_sheet(); super.choose_background()
func make_importer(): return MobileImporter.new()
func save():
	if busy(): return
	if not save_uri.is_empty(): save_to(save_uri)
	elif not model.path.begins_with("content://") and model.path.get_extension().to_lower()=="papng" and not model.path.begins_with("user://"): super.save()
	else: save_as()
func save_as():
	save_dialog.current_file=(display_path.get_basename() if not display_path.is_empty() else "untitled")+".papng"
	save_dialog.popup_centered_ratio(0.9)
func save_to(path: String):
	if not path.begins_with("content://"): super.save_to(path); return
	canvas.stop_gesture(); start_job("save",path)
func write_document(document, path: String) -> bool:
	if not path.begins_with("content://"): return super.write_document(document,path)
	# Validate and retain a local copy before touching the provider's document.
	if not document.save_file("user://pending-export.papng"): return false
	var bytes=FileAccess.get_file_as_bytes("user://pending-export.papng")
	var failure=write_uri(path,bytes)
	if not failure.is_empty(): document.error=failure; return false
	return true
static func write_uri(path: String, bytes: PackedByteArray) -> String:
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file==null: return "문서에 쓸 수 없습니다. 다른 이름으로 저장해 위치를 다시 선택하세요."
	file.store_buffer(bytes); file.flush(); var result=file.get_error(); file.close()
	if result!=OK: return "문서 저장에 실패했습니다. 앱의 임시 사본은 유지됩니다. 다른 위치로 다시 저장하세요."
	# SAF providers can truncate or delay writes; success requires readable equality.
	if FileAccess.get_file_as_bytes(path)!=bytes: return "저장 결과를 확인하지 못했습니다. 다른 위치로 다시 저장하세요."
	return ""
func export_png(path: String):
	if not path.begins_with("content://"): super.export_png(path); return
	update_preview(); var failure=write_uri(path,mini.texture.get_image().save_png_to_buffer())
	notify("현재 합성 프레임을 PNG로 내보냈습니다." if failure.is_empty() else failure)
func bind_model(next):
	display_path=""; save_uri=""; last_recovery=-1; document_generation+=1
	super.bind_model(next)
	if mobile_ready and not recovery_pending: DirAccess.remove_absolute("user://recovery.papng")
func finish_job():
	var kind=job_kind
	super.finish_job()
	if job_cancelled or not job_result.get("ok",false):
		if kind=="open": recovery_pending=false
		return
	if kind=="open" and OS.is_debug_build(): print("PAPNG_EDITOR_OPEN frames=%d size=%dx%d" % [model.frames.size(),model.width,model.height])
	if kind in ["open","save"]:
		if recovery_pending:
			recovery_pending=false; model.path=""; model.saved_revision=-1; display_path="복구한 이미지"; notify("복구했습니다. 저장 위치를 선택해 PAPNG로 저장하세요.")
		else:
			display_path=MobileImporter.display_name(job_result.path)
			if kind=="save": save_uri=job_result.path; DirAccess.remove_absolute("user://recovery.papng")
		refresh_all()
	if kind=="import": adapt_controls(import_dialog); fit_dialog(import_dialog)
func _process(delta):
	super._process(delta)
	if not mobile_ready: return
	if recovery_worker!=null and not recovery_worker.is_alive():
		recovery_worker.wait_to_finish(); recovery_worker=null
		if recovery_result and recovery_generation==document_generation and model.dirty():
			if DirAccess.rename_absolute("user://recovery-next.papng","user://recovery.papng")==OK: last_recovery=recovery_revision
		elif FileAccess.file_exists("user://recovery-next.papng"): DirAccess.remove_absolute("user://recovery-next.papng")
	var reported_keyboard=ceili(DisplayServer.virtual_keyboard_get_height()/get_window().content_scale_factor) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0
	var viewport_size=get_viewport_rect().size
	if reported_keyboard==0: unobscured_size=viewport_size
	# adjustResize can already remove the keyboard area from the viewport.
	var resized_height=maxf(0,unobscured_size.y-viewport_size.y) if is_equal_approx(unobscured_size.x,viewport_size.x) else 0.0
	var keyboard=maxi(0,reported_keyboard-ceili(resized_height))
	if keyboard!=keyboard_height: keyboard_height=keyboard; layout_mobile()
	paste_bar.visible=not canvas.floating.is_empty()
	if import_dialog.visible: fit_dialog(import_dialog)
	canvas.enabled=not modal_open() and not busy()
	intent_elapsed+=delta
	if intent_elapsed>0.4: intent_elapsed=0; poll_intent()
	recovery_clock+=delta
	if recovery_clock>30 and not busy() and not canvas.dragging:
		recovery_clock=0; backup_work()
func backup_work():
	if not mobile_ready or busy() or recovery_worker!=null or model.revision==last_recovery or not model.dirty(): return
	var copy=Model.new(); copy.restore(model.state()); copy.ancillary=model.ancillary.duplicate(true)
	recovery_revision=model.revision; recovery_generation=document_generation; recovery_result=false
	recovery_worker=Thread.new()
	if recovery_worker.start(func(): recovery_result=copy.save_file("user://recovery-next.papng"))!=OK: recovery_worker=null
func poll_intent():
	if OS.get_name()!="Android" or busy() or modal_open(): return
	var activity=Engine.get_singleton("AndroidRuntime").getActivity(); var intent=activity.getIntent()
	if intent==null or intent.hashCode()==intent_id: return
	intent_id=intent.hashCode(); var uri=null
	if intent.getAction()=="android.intent.action.VIEW": uri=intent.getData()
	elif intent.getAction()=="android.intent.action.SEND": uri=intent.getParcelableExtra("android.intent.extra.STREAM")
	if uri==null: return
	var path=str(uri.toString()); var name=MobileImporter.display_name(path)
	if name.get_extension().to_lower() in ["papng","apng","png"]: request_open(path)
	else: import_path(path)
func modal_open() -> bool: return (sheet!=null and sheet.visible) or super.modal_open()
func show_distributions(): distribution_dialog.open_palette()
func show_settings(): show_sheet("view")
func show_help():
	notice_dialog.dialog_text="한 손가락으로 그리거나 선택합니다.\n두 손가락으로 확대·이동합니다 (정수 배율).\n이동 아이콘을 켜면 한 손가락으로 화면을 옮깁니다.\n\n도구 아이콘 아래 알파벳은 키보드 단축키입니다.\n색상칩을 눌러 RGBA를 선택합니다.\n가져온 이미지: 드래그로 배치 → ✓ 적용.\n\n속성: 프레임·마스크·소켓·힌트·클립.\n보기: 격자·십자선·마스크 강조·어니언.\n좌측 미니맵은 1:1 합성 결과입니다.\n색상각·부속 연결은 미리보기 전용입니다.\n\n작업은 30초마다 앱 안에 복구 사본을 남깁니다.\n파일로 보관하려면 반드시 저장을 누르세요."
	notice_dialog.popup_centered_clamped(Vector2i(370,460),0.9)
func _notification(what):
	if what==NOTIFICATION_APPLICATION_PAUSED:
		if canvas!=null: canvas.stop_gesture(); backup_work()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if sheet!=null and sheet.visible: hide_sheet()
		elif canvas!=null and not canvas.floating.is_empty(): canvas.cancel_paste()
		elif not modal_open(): guard(quit_editor)
	elif what==NOTIFICATION_WM_CLOSE_REQUEST:
		if not busy(): guard(quit_editor)
	else: super._notification(what)

func quit_editor():
	if recovery_worker!=null: recovery_worker.wait_to_finish(); recovery_worker=null
	for file in ["user://recovery.papng","user://recovery-next.papng"]:
		if FileAccess.file_exists(file): DirAccess.remove_absolute(file)
	get_tree().quit()
func _exit_tree():
	if recovery_worker!=null: recovery_worker.wait_to_finish()
	if worker!=null: job_cancelled=true; worker.wait_to_finish()
