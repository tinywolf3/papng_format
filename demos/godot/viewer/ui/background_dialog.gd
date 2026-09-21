extends AcceptDialog
const Decoder = preload("res://core/background_image.gd")
var view
var background_choice: OptionButton
var tint: ColorPickerButton
var image_info: Label
var show_image: CheckBox
var x_value: SpinBox
var y_value: SpinBox
var scale_value: SpinBox
var opacity_value: SpinBox
var opacity_slider: HSlider
var fit_button: Button
var original_button: Button
var remove_button: Button
var load_button: Button
var file_dialog: FileDialog
var notice: Label
var worker: Thread
var result: Dictionary = {}
var started = 0
var syncing = false

func _ready():
	title = "뷰어 배경"; ok_button_text = "닫기"; get_ok_button().custom_minimum_size.y = 44
	wrap_controls = false
	var scroll = ScrollContainer.new(); scroll.custom_minimum_size = Vector2(290,250); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	var box = VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",6); scroll.add_child(box)
	background_choice = OptionButton.new(); background_choice.add_item("체크무늬"); background_choice.add_item("단색"); background_choice.custom_minimum_size.y = 44; box.add_child(background_choice)
	background_choice.item_selected.connect(func(index): view.background_mode = index; sync(); view.queue_redraw())
	tint = ColorPickerButton.new(); tint.edit_alpha = false; tint.custom_minimum_size.y = 44; box.add_child(tint)
	tint.color_changed.connect(func(color): view.background_color = Color(color,1.0); view.queue_redraw())
	var files = HFlowContainer.new(); box.add_child(files)
	load_button = button(files,"이미지…",func(): file_dialog.popup_centered_ratio(0.85))
	remove_button = button(files,"제거",func(): view.clear_reference(); sync())
	image_info = label(box,""); image_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	show_image = CheckBox.new(); show_image.text = "이미지 표시"; show_image.custom_minimum_size.y = 44; box.add_child(show_image)
	show_image.toggled.connect(func(on): if not syncing: view.reference_visible = on; view.queue_redraw())
	x_value = spin(box,"X (px)",-1000000,1000000,0.1); y_value = spin(box,"Y (px)",-1000000,1000000,0.1)
	scale_value = spin(box,"배율 (%)",0.01,100000,0.01)
	x_value.tooltip_text = "PAPNG 왼쪽 위를 기준으로 배경 이미지 왼쪽 위의 X 좌표"
	y_value.tooltip_text = "PAPNG 왼쪽 위를 기준으로 배경 이미지 왼쪽 위의 Y 좌표"
	scale_value.tooltip_text = "100% = 배경 원본 이미지 1픽셀이 PAPNG 1픽셀"
	for field in [x_value,y_value,scale_value]: field.value_changed.connect(func(_value): apply_transform())
	var sizes = HFlowContainer.new(); box.add_child(sizes)
	fit_button = button(sizes,"이미지에 맞춤",func(): view.fit_reference(); sync())
	original_button = button(sizes,"100%",func(): view.reference_scale = 1.0; view.queue_redraw(); sync())
	opacity_value = spin(box,"불투명도 (%)",0,100,1)
	opacity_slider = HSlider.new(); opacity_slider.max_value = 100; opacity_slider.step = 1; opacity_slider.custom_minimum_size.y = 44; box.add_child(opacity_slider)
	opacity_value.value_changed.connect(set_opacity); opacity_slider.value_changed.connect(set_opacity)
	notice = label(box,""); notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var note = label(box,"배경은 확대·이동을 함께 따릅니다.
파일을 바꿔도 유지되며 원본에는 저장하지 않습니다."); note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.add_theme_font_size_override("font_size",13)
	file_dialog = FileDialog.new(); file_dialog.title = "배경 이미지 선택"; file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; file_dialog.access = FileDialog.ACCESS_FILESYSTEM; file_dialog.use_native_dialog = true
	file_dialog.filters = PackedStringArray(["*.png,*.apng,*.papng,*.jpg,*.jpeg,*.webp,*.bmp,*.svg;배경 이미지", "*;모든 파일"])
	file_dialog.file_selected.connect(load_background); add_child(file_dialog)
	sync()
func label(parent: Node, text: String) -> Label:
	var item = Label.new(); item.text = text; parent.add_child(item); return item
func button(parent: Node, text: String, action: Callable) -> Button:
	var item = Button.new(); item.text = text; item.custom_minimum_size.y = 44; item.pressed.connect(action); parent.add_child(item); return item
func spin(parent: Node, caption: String, low: float, high: float, step: float) -> SpinBox:
	var row = HBoxContainer.new(); parent.add_child(row); label(row,caption).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var item = SpinBox.new(); item.min_value = low; item.max_value = high; item.step = step; item.custom_minimum_size = Vector2(125,44); row.add_child(item); return item
func open_settings():
	sync(); popup_centered_clamped(Vector2i(390,600),0.9)
func sync():
	if background_choice == null: return
	syncing = true
	var has_image = view.reference_texture != null
	background_choice.select(view.background_mode); tint.color = view.background_color; tint.visible = view.background_mode == 1
	image_info.text = "%d × %d px" % [view.reference_size.x,view.reference_size.y] if has_image else "참고 이미지 없음"
	load_button.disabled = worker != null or view.info.is_empty()
	show_image.set_pressed_no_signal(view.reference_visible and has_image); show_image.disabled = not has_image
	x_value.set_value_no_signal(view.reference_position.x); y_value.set_value_no_signal(view.reference_position.y); scale_value.set_value_no_signal(view.reference_scale*100)
	opacity_value.set_value_no_signal(view.reference_opacity*100); opacity_slider.set_value_no_signal(view.reference_opacity*100)
	for field in [x_value,y_value,scale_value,opacity_value]: field.editable = has_image
	for item in [fit_button,original_button,remove_button]: item.disabled = not has_image or worker != null
	fit_button.disabled = fit_button.disabled or view.info.is_empty()
	opacity_slider.editable = has_image
	if worker == null: notice.text = "PAPNG·PNG·APNG를 먼저 열면 이미지 배경을 추가할 수 있습니다." if view.info.is_empty() else ""
	syncing = false
func apply_transform():
	if syncing: return
	view.reference_position = Vector2(x_value.value,y_value.value); view.reference_scale = scale_value.value/100.0; view.queue_redraw()
func set_opacity(value: float):
	if syncing: return
	view.reference_opacity = value/100.0; opacity_value.set_value_no_signal(value); opacity_slider.set_value_no_signal(value); view.queue_redraw()
func load_background(path: String):
	if worker != null: return
	result = {}; started = Time.get_ticks_msec(); worker = Thread.new()
	if worker.start(func(): result = Decoder.load_image(path)) != OK:
		worker = null; notice.text = "배경 로딩을 시작하지 못했습니다."; return
	sync()
func _process(_delta):
	if worker == null: return
	notice.text = "배경 이미지를 읽는 중 · %.1f초" % ((Time.get_ticks_msec()-started)/1000.0)
	if worker.is_alive(): return
	worker.wait_to_finish(); worker = null
	var error = result.get("error","배경 로딩 실패")
	if error.is_empty(): view.set_reference(result.image,result.size)
	result = {}; sync(); notice.text = error if not error.is_empty() else "배경을 불러왔습니다. 위치·배율·불투명도를 조절할 수 있습니다."
func _exit_tree():
	if worker != null: worker.wait_to_finish(); worker = null
