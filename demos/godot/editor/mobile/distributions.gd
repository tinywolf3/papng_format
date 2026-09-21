extends ConfirmationDialog
## Structured editing for the shared distribution palette on a touch screen.
const UI=preload("res://ui/widgets.gd")
var host
var definitions: Array=[]
var selected: OptionButton
var kind: OptionButton
var items: VBoxContainer
var rows: Array=[]
var loading=false
func _ready():
	title="공유 랜덤 분포"; ok_button_text="적용"; cancel_button_text="취소"; wrap_controls=false
	var box=VBoxContainer.new(); add_child(box)
	UI.label(box,"0번은 균등분포입니다. 추가 분포는 1~255번입니다.").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	selected=UI.options(box,"",[]); selected.item_selected.connect(func(index): store_current(); selected.set_meta("previous",index); rebuild())
	var buttons=UI.row(box)
	UI.button(buttons,"분포 추가",func():
		store_current()
		if definitions.size()>=255: host.notify("추가 분포는 최대 255개입니다."); return
		definitions.append({"kind":0,"valid":true,"items":[]}); refresh_list(definitions.size()-1))
	UI.button(buttons,"마지막 분포 삭제",func():
		store_current()
		if definitions.is_empty(): return
		definitions.pop_back(); refresh_list(definitions.size()-1))
	kind=UI.options(box,"분포 종류",["균등","중앙 우선","작은 값 우선","큰 값 우선","가중치 숫자 배열"])
	kind.item_selected.connect(func(index):
		if not loading and selected.selected>=0: store_current(); definitions[selected.selected].kind=index; rebuild())
	var scroll=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.custom_minimum_size.y=140; box.add_child(scroll)
	items=VBoxContainer.new(); items.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(items)
	UI.button(box,"숫자 항목 추가",func():
		store_current()
		if selected.selected<0 or kind.selected!=4: host.notify("가중치 숫자 배열 분포를 선택하세요."); return
		definitions[selected.selected].items.append({"value":0,"weight":1}); rebuild())
	confirmed.connect(func():
		store_current()
		host.edit("공유 분포 편집",func(): host.model.distributions=[{"kind":0,"valid":true,"items":[]}]+definitions.duplicate(true); host.model.touch())
		if not host.action_error.is_empty(): popup_centered_ratio(0.9))
func open_palette():
	definitions=host.model.distributions.slice(1).duplicate(true); refresh_list(0); host.adapt_controls(self); popup_centered_ratio(0.9)
func refresh_list(index: int):
	selected.clear()
	for i in definitions.size(): selected.add_item("분포 %d" % (i+1))
	if not definitions.is_empty(): selected.select(clampi(index,0,definitions.size()-1))
	selected.set_meta("previous",selected.selected); rebuild()
func store_current():
	var index=int(selected.get_meta("previous",-1))
	if index<0 or index>=definitions.size(): return
	if definitions[index].kind==4:
		var values=[]
		for row in rows: values.append({"value":int(row[0].value),"weight":int(row[1].value)})
		definitions[index].items=values
func rebuild():
	loading=true
	for node in items.get_children(): items.remove_child(node); node.queue_free()
	rows.clear(); var index=selected.selected; kind.disabled=index<0
	if index>=0:
		var d=definitions[index]; kind.select(d.kind)
		if d.kind==4:
			for i in d.items.size():
				var entry=d.items[i]; var group=VBoxContainer.new(); items.add_child(group)
				var heading=UI.row(group); UI.label(heading,"항목 %d" % (i+1)).size_flags_horizontal=Control.SIZE_EXPAND_FILL
				UI.button(heading,"삭제",func(): store_current(); definitions[index].items.remove_at(i); rebuild())
				var value=UI.spin(group,"숫자",-8388608,8388607); value.value=entry.value
				var weight=UI.spin(group,"가중치",0,255); weight.value=entry.weight; rows.append([value,weight]); group.add_child(HSeparator.new())
		else: UI.label(items,"이 분포에는 추가 매개변수가 없습니다.").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	host.adapt_controls(self); loading=false
