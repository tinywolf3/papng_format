extends RefCounted
static func label(parent: Node, text: String) -> Label:
	var item=Label.new(); item.text=text; parent.add_child(item); return item
static func button(parent: Node, text: String, action: Callable, tooltip: String = "") -> Button:
	var item=Button.new(); item.text=text; item.tooltip_text=tooltip; item.custom_minimum_size.y=32; item.pressed.connect(action); parent.add_child(item); return item
static func row(parent: Node) -> HBoxContainer:
	var item=HBoxContainer.new(); parent.add_child(item); return item
static func spin(parent: Node, text: String, low: float, high: float, step: float = 1) -> SpinBox:
	var line=row(parent)
	var caption=label(line,text); caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var item=SpinBox.new(); item.min_value=low; item.max_value=high; item.step=step; item.custom_minimum_size.x=112; line.add_child(item); return item
static func entry(parent: Node, text: String) -> LineEdit:
	label(parent,text); var item=LineEdit.new(); parent.add_child(item); return item
static func options(parent: Node, text: String, choices: Array) -> OptionButton:
	if not text.is_empty(): label(parent,text)
	var item=OptionButton.new(); item.fit_to_longest_item=false; item.clip_text=true; item.custom_minimum_size.y=30
	for choice in choices: item.add_item(choice)
	parent.add_child(item); return item
static func check(parent: Node, text: String, enabled: bool = false) -> CheckBox:
	var item=CheckBox.new(); item.text=text; item.button_pressed=enabled; parent.add_child(item); return item
static func tab(tabs: TabContainer, name: String) -> VBoxContainer:
	var scroll=ScrollContainer.new(); scroll.name=name; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; tabs.add_child(scroll)
	var margin=MarginContainer.new(); margin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,8)
	scroll.add_child(margin); var content=VBoxContainer.new(); content.add_theme_constant_override("separation",7); margin.add_child(content); return content
