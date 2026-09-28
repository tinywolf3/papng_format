extends Control
signal centered(point: Vector2)
var texture: ImageTexture
var viewport_rect=Rect2()
var fit_to_panel=false
func _ready(): texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; mouse_filter=Control.MOUSE_FILTER_STOP
func set_image(image: Image):
	texture=ImageTexture.create_from_image(image)
	if not fit_to_panel: custom_minimum_size=Vector2(image.get_size())
	queue_redraw()
func image_rect() -> Rect2:
	if texture==null: return Rect2()
	var dimensions=Vector2(texture.get_size())
	if not fit_to_panel: return Rect2(Vector2.ZERO,dimensions)
	var factor=minf(1.0,minf(size.x/dimensions.x,size.y/dimensions.y))
	var drawn=dimensions*factor
	return Rect2((size-drawn)/2,drawn)
func _gui_input(event):
	if texture==null: return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var area=image_rect()
		if area.has_point(event.position): centered.emit((event.position-area.position)*Vector2(texture.get_size())/area.size)
func _draw():
	if texture==null: return
	draw_rect(Rect2(Vector2.ZERO,size),Color("222f3b"))
	var area=image_rect()
	draw_texture_rect(texture,area,false)
	var visible_area=viewport_rect.intersection(Rect2(Vector2.ZERO,texture.get_size()))
	if visible_area.has_area():
		var factor=area.size/Vector2(texture.get_size())
		draw_rect(Rect2(area.position+visible_area.position*factor,visible_area.size*factor),Color("9cf4d1"),false,1)
