extends ConfirmationDialog
const Crop = preload("res://ui/crop_view.gd")
const Importer = preload("res://core/import_image.gd")
signal copied(data: Dictionary)
var crop_view
var preview: TextureRect
var status: Label
var controls: Dictionary = {}
var ratio: CheckBox
var sampling: OptionButton
var levels: SpinBox
var result: Image
var updating=false
func _ready():
	title="프레임 이미지 가져오기 · 오려내기 / 픽셀화"; ok_button_text="선택 영역 복사 → 편집기"; cancel_button_text="취소"
	var column=VBoxContainer.new(); add_child(column)
	var help=Label.new(); help.text="원본에서 드래그해 영역 선택 · 휠로 확대/축소 · 가운데 버튼으로 이동"; column.add_child(help)
	var split=HSplitContainer.new(); split.custom_minimum_size=Vector2(780,350); split.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(split)
	var left=VBoxContainer.new(); split.add_child(left)
	var bar=HBoxContainer.new(); left.add_child(bar)
	for info in [["화면에 맞춤",0],["−",1],["+",2],["1:1",3]]:
		var b=Button.new(); b.text=info[0]; bar.add_child(b)
		b.pressed.connect(func():
			if info[1]==0: crop_view.fit()
			elif info[1]==3: crop_view.zoom=1; crop_view.queue_redraw()
			else: crop_view.zoom_by(0.8 if info[1]==1 else 1.25))
	crop_view=Crop.new(); crop_view.custom_minimum_size=Vector2(420,280); crop_view.size_flags_vertical=Control.SIZE_EXPAND_FILL; left.add_child(crop_view)
	crop_view.selected.connect(func(rect): set_crop(rect); values_changed("w"))
	var right=VBoxContainer.new(); right.custom_minimum_size.x=250; split.add_child(right)
	var label=Label.new(); label.text="픽셀화 결과"; right.add_child(label)
	preview=TextureRect.new(); preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; preview.custom_minimum_size=Vector2(240,240); preview.size_flags_vertical=Control.SIZE_EXPAND_FILL; right.add_child(preview)
	var coordinates=HFlowContainer.new(); column.add_child(coordinates)
	for key in ["x","y","w","h","out_w","out_h"]:
		var group=HBoxContainer.new(); coordinates.add_child(group)
		var caption=Label.new(); caption.text={"x":"X","y":"Y","w":"자르기 W","h":"H","out_w":"출력 W","out_h":"H"}[key]; group.add_child(caption)
		var spin=SpinBox.new(); spin.min_value=0 if key in ["x","y"] else 1; spin.max_value=65535 if not key.begins_with("out") else 2048; spin.custom_minimum_size.x=85; group.add_child(spin); controls[key]=spin
		spin.value_changed.connect(func(_value): values_changed(key))
	var options=HBoxContainer.new(); column.add_child(options)
	ratio=CheckBox.new(); ratio.text="출력 비율 유지"; ratio.button_pressed=true; options.add_child(ratio)
	sampling=OptionButton.new(); for name in ["최근접 · 픽셀 유지","선형 · 부드럽게","Lanczos · 축소"]: sampling.add_item(name)
	options.add_child(sampling); sampling.item_selected.connect(func(_index): rebuild())
	var c=Label.new(); c.text="채널별 색 단계 (0 = 유지)"; options.add_child(c)
	levels=SpinBox.new(); levels.min_value=0; levels.max_value=64; options.add_child(levels); levels.value_changed.connect(func(_v): rebuild())
	status=Label.new(); column.add_child(status)
	confirmed.connect(func():
		if result!=null: copied.emit({"width":result.get_width(),"height":result.get_height(),"rgba":result.get_data(),"mask":PackedByteArray()}))
func open_image(source: Image, name: String):
	crop_view.set_image(source); set_crop(Rect2i(Vector2i.ZERO,source.get_size()))
	updating=true; controls.out_w.value=mini(64,source.get_width()); controls.out_h.value=maxi(1,roundi(controls.out_w.value*source.get_height()/source.get_width())); updating=false
	title="프레임 이미지 가져오기 · "+name
	popup_centered_clamped(Vector2i(1050,650),0.94); crop_view.call_deferred("fit"); rebuild()
func set_crop(rect: Rect2i):
	updating=true
	controls.x.value=rect.position.x; controls.y.value=rect.position.y; controls.w.value=rect.size.x; controls.h.value=rect.size.y
	updating=false
func values_changed(key: String):
	if updating or crop_view.source==null: return
	if ratio.button_pressed:
		updating=true
		if key=="out_h": controls.out_w.value=maxi(1,roundi(controls.out_h.value*controls.w.value/controls.h.value))
		else: controls.out_h.value=maxi(1,roundi(controls.out_w.value*controls.h.value/controls.w.value))
		updating=false
	rebuild()
func rebuild():
	if crop_view.source==null: return
	var rect=Rect2i(int(controls.x.value),int(controls.y.value),int(controls.w.value),int(controls.h.value)).intersection(Rect2i(Vector2i.ZERO,crop_view.source.get_size()))
	crop_view.crop=rect; crop_view.queue_redraw()
	result=Importer.pixelize(crop_view.source,rect,Vector2i(int(controls.out_w.value),int(controls.out_h.value)),[Image.INTERPOLATE_NEAREST,Image.INTERPOLATE_BILINEAR,Image.INTERPOLATE_LANCZOS][sampling.selected],int(levels.value))
	preview.texture=ImageTexture.create_from_image(result) if result!=null else null
	get_ok_button().disabled=result==null
	status.text="%s × %s → %s × %s px · 클립보드에 복사한 뒤 위치를 정해 붙입니다" % [rect.size.x,rect.size.y,controls.out_w.value,controls.out_h.value] if result!=null else "원본 범위 안에서 유효한 영역을 선택하세요."
