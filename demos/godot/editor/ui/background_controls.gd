extends VBoxContainer
## Shared desktop/touch controls for a non-destructive canvas reference.
const UI=preload("res://ui/widgets.gd")
var host
var mode: OptionButton
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
var syncing=false

func _ready():
	add_theme_constant_override("separation",5)
	mode=UI.options(self,"바탕",["체크무늬","단색"])
	mode.item_selected.connect(func(value): host.canvas.background_mode=value; sync(); host.canvas.queue_redraw())
	tint=ColorPickerButton.new(); tint.edit_alpha=false; tint.custom_minimum_size.y=36; add_child(tint)
	tint.tooltip_text="단색 배경 색상"; tint.color_changed.connect(func(value): host.canvas.background_color=Color(value,1.0); host.canvas.queue_redraw())
	var files=HFlowContainer.new(); add_child(files)
	UI.button(files,"이미지…",func(): host.choose_background(),"참고할 외부 이미지를 배경에 불러옵니다.")
	remove_button=UI.button(files,"제거",func(): host.canvas.clear_reference(); sync())
	image_info=UI.label(self,"참고 이미지 없음"); image_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	show_image=UI.check(self,"이미지 표시")
	show_image.toggled.connect(func(on): if not syncing: host.canvas.reference_visible=on; host.canvas.queue_redraw())
	x_value=UI.spin(self,"X",-1000000,1000000,0.1); x_value.tooltip_text="캔버스 왼쪽에서 이미지 왼쪽 위까지의 픽셀 거리"
	y_value=UI.spin(self,"Y",-1000000,1000000,0.1); y_value.tooltip_text="캔버스 위에서 이미지 왼쪽 위까지의 픽셀 거리"
	scale_value=UI.spin(self,"배율",0.01,100000,0.01); scale_value.suffix="%"; scale_value.tooltip_text="100% = 이미지 1픽셀이 캔버스 1픽셀. 가로세로 비율을 유지합니다."
	for spin in [x_value,y_value,scale_value]:
		spin.custom_minimum_size.x=96; spin.value_changed.connect(func(_value): apply_transform())
	var sizes=HFlowContainer.new(); add_child(sizes)
	fit_button=UI.button(sizes,"맞춤",func(): host.canvas.fit_reference(); sync(),"이미지 전체가 캔버스에 들어오도록 가운데 배치")
	original_button=UI.button(sizes,"100%",func(): host.canvas.reference_scale=1.0; host.canvas.queue_redraw(); sync(),"원본 픽셀 배율로, 위치는 유지")
	opacity_value=UI.spin(self,"불투명도",0,100); opacity_value.suffix="%"; opacity_value.custom_minimum_size.x=80
	opacity_slider=HSlider.new(); opacity_slider.min_value=0; opacity_slider.max_value=100; opacity_slider.step=1; add_child(opacity_slider)
	opacity_value.value_changed.connect(set_opacity); opacity_slider.value_changed.connect(set_opacity)
	var note=UI.label(self,"편집 참고용 · 저장/내보내기에는 포함되지 않습니다.")
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; note.add_theme_font_size_override("font_size",12)
	sync()
func sync():
	if mode==null: return
	syncing=true
	var canvas=host.canvas; var has_image=canvas.reference_texture!=null
	mode.select(canvas.background_mode); tint.color=canvas.background_color; tint.visible=canvas.background_mode==1
	image_info.text="%d × %d px" % [canvas.reference_texture.get_width(),canvas.reference_texture.get_height()] if has_image else "참고 이미지 없음"
	show_image.set_pressed_no_signal(canvas.reference_visible and has_image); show_image.disabled=not has_image
	x_value.set_value_no_signal(canvas.reference_position.x); y_value.set_value_no_signal(canvas.reference_position.y)
	scale_value.set_value_no_signal(canvas.reference_scale*100)
	opacity_value.set_value_no_signal(canvas.reference_opacity*100); opacity_slider.set_value_no_signal(canvas.reference_opacity*100)
	for spin in [x_value,y_value,scale_value,opacity_value]: spin.editable=has_image
	for button in [fit_button,original_button,remove_button]: button.disabled=not has_image
	opacity_slider.editable=has_image; syncing=false
func apply_transform():
	if syncing: return
	host.canvas.reference_position=Vector2(x_value.value,y_value.value)
	host.canvas.reference_scale=scale_value.value/100.0; host.canvas.queue_redraw()
func set_opacity(value: float):
	if syncing: return
	host.canvas.reference_opacity=value/100.0
	opacity_value.set_value_no_signal(value); opacity_slider.set_value_no_signal(value); host.canvas.queue_redraw()
