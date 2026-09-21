extends Control
signal centered(point: Vector2)
var texture: ImageTexture
var viewport_rect=Rect2()
func _ready(): texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; mouse_filter=Control.MOUSE_FILTER_STOP
func set_image(image: Image):
	texture=ImageTexture.create_from_image(image); custom_minimum_size=Vector2(image.get_size()); queue_redraw()
func _gui_input(event):
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed: centered.emit(event.position)
func _draw():
	if texture==null: return
	draw_rect(Rect2(Vector2.ZERO,size),Color("222f3b"))
	draw_texture(texture,Vector2.ZERO)
	draw_rect(viewport_rect.intersection(Rect2(Vector2.ZERO,texture.get_size())),Color("9cf4d1"),false,1)
