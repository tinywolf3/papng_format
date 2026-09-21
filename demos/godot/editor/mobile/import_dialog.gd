extends "res://ui/import_dialog.gd"
const UI=preload("res://ui/widgets.gd")
var pages: TabContainer
func _ready():
	title="이미지 가져오기"; ok_button_text="복사해서 배치"; cancel_button_text="취소"
	var column=VBoxContainer.new(); add_child(column)
	var steps=UI.row(column)
	for i in 2:
		var button=UI.button(steps,["1 · 오려내기","2 · 픽셀화"][i],func(): pages.current_tab=i)
		button.custom_minimum_size.y=48; button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	pages=TabContainer.new(); pages.tabs_visible=false; pages.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(pages)
	var first_scroll=ScrollContainer.new(); first_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; pages.add_child(first_scroll)
	var first=VBoxContainer.new(); first.size_flags_horizontal=Control.SIZE_EXPAND_FILL; first_scroll.add_child(first)
	var help=UI.label(first,"드래그: 영역 선택 · 확대 후에는 이동 모드 사용"); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var bar=UI.row(first)
	UI.button(bar,"맞춤",func(): crop_view.fit())
	UI.button(bar,"−",func(): crop_view.zoom_by(0.8)); UI.button(bar,"+",func(): crop_view.zoom_by(1.25))
	UI.check(bar,"이동").toggled.connect(func(value): crop_view.move_mode=value)
	crop_view=preload("res://mobile/touch_crop.gd").new(); crop_view.custom_minimum_size=Vector2(220,240); crop_view.size_flags_vertical=Control.SIZE_EXPAND_FILL; first.add_child(crop_view)
	crop_view.selected.connect(func(rect): set_crop(rect); values_changed("w"))
	var coords=GridContainer.new(); coords.columns=2; coords.size_flags_horizontal=Control.SIZE_EXPAND_FILL; first.add_child(coords)
	for key in ["x","y","w","h"]:
		controls[key]=UI.spin(coords,{"x":"X","y":"Y","w":"너비 W","h":"높이 H"}[key],0 if key in ["x","y"] else 1,65535)
		controls[key].get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
		controls[key].custom_minimum_size.x=85; controls[key].value_changed.connect(func(_v): values_changed(key))
	var second_scroll=ScrollContainer.new(); second_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; pages.add_child(second_scroll)
	var second=VBoxContainer.new(); second.size_flags_horizontal=Control.SIZE_EXPAND_FILL; second_scroll.add_child(second)
	UI.label(second,"픽셀화 미리보기")
	preview=TextureRect.new(); preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; preview.custom_minimum_size=Vector2(200,160); second.add_child(preview)
	for key in ["out_w","out_h"]:
		controls[key]=UI.spin(second,"출력 너비" if key=="out_w" else "출력 높이",1,2048); controls[key].value_changed.connect(func(_v): values_changed(key))
	ratio=UI.check(second,"비율 유지",true)
	sampling=UI.options(second,"보간",["최근접 · 픽셀 유지","선형 · 부드럽게","Lanczos · 축소"]); sampling.item_selected.connect(func(_i): rebuild())
	levels=UI.spin(second,"채널별 색 단계 (0 = 유지)",0,64); levels.value_changed.connect(func(_v): rebuild())
	status=UI.label(column,""); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	confirmed.connect(func():
		if result!=null: copied.emit({"width":result.get_width(),"height":result.get_height(),"rgba":result.get_data(),"mask":PackedByteArray()}))
func open_image(source: Image, name: String):
	crop_view.set_image(source); set_crop(Rect2i(Vector2i.ZERO,source.get_size())); pages.current_tab=0
	updating=true; controls.out_w.value=mini(64,source.get_width()); controls.out_h.value=clampi(roundi(controls.out_w.value*source.get_height()/source.get_width()),1,2048); updating=false
	title="이미지 가져오기 · "+name; popup_centered_ratio(0.94); crop_view.fit.call_deferred(); rebuild()
