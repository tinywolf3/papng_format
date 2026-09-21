extends "res://ui/crop_view.gd"
var move_mode=false
func _gui_input(event):
	# Godot mouse emulation keeps crop selection and single-finger panning identical.
	if move_mode and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		panning=event.pressed; accept_event(); return
	super._gui_input(event)
