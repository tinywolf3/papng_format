extends "res://ui/pixel_canvas.gd"
## Touch is handled before mouse emulation; widgets still use normal Android taps.
var enabled=true
var move_mode=false
var clear_mask=false
var fingers: Dictionary={}
var first_position=Vector2.ZERO
var last_position=Vector2.ZERO
var gesture=false
var stroke_started=false
var initial_zoom=1
var initial_distance=1.0
var initial_anchor=Vector2.ZERO
var selection_before=Rect2i()
var paste_before=Vector2i.ZERO
func _gui_input(event):
	if event is InputEventMouse and event.device==-1: return
	super._gui_input(event)
func _input(event):
	if not enabled or model==null: return
	if event is InputEventScreenTouch:
		var local=get_global_transform_with_canvas().affine_inverse()*event.position
		if event.pressed:
			if not Rect2(Vector2.ZERO,size).has_point(local): return
			fingers[event.index]=local
			if fingers.size()==1:
				first_position=local; last_position=local; gesture=false; stroke_started=false
				selection_before=selection; paste_before=floating_position; update_cursor(local)
			elif fingers.size()==2:
				# Roll back the first finger's uncommitted stroke before pinching.
				if stroke_started: model.cancel(); dragging=false; refresh()
				selection=selection_before; floating_position=paste_before; gesture=true
				var points=fingers.values(); var center=(points[0]+points[1])/2
				initial_distance=maxf(1,points[0].distance_to(points[1])); initial_zoom=zoom
				update_origin(); initial_anchor=(center-origin)/zoom
		elif fingers.has(event.index):
			if event.canceled:
				if stroke_started: model.cancel(); dragging=false; refresh()
				gesture=true
			elif fingers.size()==1 and not gesture and not move_mode:
				if not stroke_started: mouse_button(first_position,true)
				mouse_button(local,false)
			fingers.erase(event.index)
			if fingers.is_empty(): dragging=false; stroke_started=false
		else: return
		get_viewport().set_input_as_handled(); queue_redraw()
	elif event is InputEventScreenDrag and fingers.has(event.index):
		var local=get_global_transform_with_canvas().affine_inverse()*event.position
		var previous_position=fingers[event.index]; fingers[event.index]=local
		if fingers.size()>=2:
			var points=fingers.values(); var center=(points[0]+points[1])/2
			zoom=clampi(roundi(initial_zoom*points[0].distance_to(points[1])/initial_distance),1,128)
			pan=center-initial_anchor*zoom-(size-Vector2(model.width,model.height)*zoom)/2
			zoom_changed.emit(zoom)
		elif move_mode: pan+=local-previous_position
		elif not gesture:
			if tool in ["fill","pick","socket"]: first_position=local
			else:
				if not stroke_started: mouse_button(first_position,true); stroke_started=true
				var motion=InputEventMouseMotion.new(); motion.position=local; motion.relative=local-last_position; motion.shift_pressed=clear_mask
				super._gui_input(motion)
		update_cursor(local); last_position=local; queue_redraw(); get_viewport().set_input_as_handled()
func mouse_button(position: Vector2, pressed: bool):
	var event=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.position=position; event.pressed=pressed; event.shift_pressed=clear_mask
	super._gui_input(event)
func update_cursor(position: Vector2):
	cursor=pixel(position); has_cursor=Rect2i(0,0,model.width,model.height).has_point(cursor)
	cursor_changed.emit(cursor,model.pixel_at(cursor)); queue_redraw()
func stop_gesture():
	super.stop_gesture(); fingers.clear(); gesture=false; stroke_started=false
func start_paste(data: Dictionary):
	super.start_paste(data); message.emit("한 손가락으로 배치한 뒤 ✓ 적용을 누르세요.")
