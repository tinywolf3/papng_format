extends Node
func _ready():
	var mobile=OS.get_name()=="Android" or "--mobile" in OS.get_cmdline_user_args()
	var editor=load("res://mobile/editor.gd" if mobile else "res://editor.gd").new()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(editor)
