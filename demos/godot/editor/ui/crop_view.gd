extends Control
signal selected(rect: Rect2i)
var source: Image
var texture: ImageTexture
var crop=Rect2i()
var zoom=1.0
var pan=Vector2.ZERO
var origin=Vector2.ZERO
var dragging=false
var panning=false
var start=Vector2i.ZERO
func _ready(): clip_contents=true; mouse_filter=Control.MOUSE_FILTER_STOP; texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; resized.connect(queue_redraw)
func set_image(image: Image):
	source=image; texture=ImageTexture.create_from_image(image); crop=Rect2i(Vector2i.ZERO,image.get_size()); pan=Vector2.ZERO
	call_deferred("fit")
func fit():
	if source==null: return
	zoom=maxf(0.01,minf((size.x-32)/source.get_width(),(size.y-32)/source.get_height())); pan=Vector2.ZERO; queue_redraw()
func zoom_by(factor: float): zoom=clampf(zoom*factor,0.01,64); queue_redraw()
func at(point: Vector2) -> Vector2i:
	return Vector2i(((point-origin)/zoom).floor()).clamp(Vector2i.ZERO,source.get_size()-Vector2i.ONE)
func _gui_input(event):
	if source==null: return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed: zoom_by(1.25)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed: zoom_by(0.8)
		elif event.button_index==MOUSE_BUTTON_MIDDLE: panning=event.pressed
		elif event.button_index==MOUSE_BUTTON_LEFT:
			dragging=event.pressed
			if dragging: start=at(event.position)
	elif event is InputEventMouseMotion:
		if panning: pan+=event.relative; queue_redraw()
		elif dragging:
			var end=at(event.position); crop=Rect2i(start.min(end),(start-end).abs()+Vector2i.ONE)
			selected.emit(crop); queue_redraw()
func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color("111820"))
	if texture==null:return
	origin=(size-Vector2(source.get_size())*zoom)/2+pan
	draw_texture_rect(texture,Rect2(origin,Vector2(source.get_size())*zoom),false)
	draw_rect(Rect2(origin+Vector2(crop.position)*zoom,Vector2(crop.size)*zoom),Color("ffd58d"),false,2)
