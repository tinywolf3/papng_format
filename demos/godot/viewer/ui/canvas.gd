extends Control
var texture: ImageTexture
var mark_texture: ImageTexture
var child_texture: ImageTexture
var info: Dictionary = {}
var child_info: Dictionary = {}
var poses: Array = []
var socket_index = 0
var highlight = false
var hints = false
var sockets = false
var zoom = 1.0
var auto_fit = true
var pan = Vector2.ZERO
var dragging = false
var origin = Vector2.ZERO
var background_mode = 0
var background_color = Color("141b25")
var reference_texture: ImageTexture
var reference_size = Vector2.ZERO
var reference_position = Vector2.ZERO
var reference_scale = 1.0
var reference_opacity = 1.0
var reference_visible = true

func set_reference(image: Image, original_size: Vector2):
	reference_texture = ImageTexture.create_from_image(image); reference_size = original_size
	reference_visible = true; reference_opacity = 1.0; fit_reference()
func clear_reference():
	reference_texture = null; reference_size = Vector2.ZERO; reference_position = Vector2.ZERO
	reference_scale = 1.0; reference_opacity = 1.0; reference_visible = true; queue_redraw()
func fit_reference():
	if reference_texture == null or info.is_empty(): return
	var dimensions = Vector2(info.width,info.height)
	reference_scale = minf(dimensions.x/reference_size.x,dimensions.y/reference_size.y)
	reference_position = (dimensions-reference_size*reference_scale)/2; queue_redraw()
func draw_reference():
	if reference_texture == null or not reference_visible or reference_opacity <= 0: return
	var rect = Rect2(origin+reference_position*zoom,reference_size*reference_scale*zoom)
	var clipped = rect.intersection(Rect2(Vector2.ZERO,size))
	if not clipped.has_area(): return
	var source = Rect2((clipped.position-rect.position)/rect.size*reference_texture.get_size(),clipped.size/rect.size*reference_texture.get_size())
	draw_texture_rect_region(reference_texture,clipped,source,Color(1,1,1,reference_opacity))

func _ready():
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)

func clear():
	texture = null; child_texture = null; mark_texture = null
	info = {}; child_info = {}; poses = []; pan = Vector2.ZERO; auto_fit = true; queue_redraw()

func image_texture(bytes: PackedByteArray, details: Dictionary) -> ImageTexture:
	if bytes.is_empty() or details.is_empty(): return null
	return ImageTexture.create_from_image(Image.create_from_data(details.width,details.height,false,Image.FORMAT_RGBA8,bytes))

func set_frame(event: Dictionary):
	texture = image_texture(event.pixels,info)
	mark_texture = image_texture(event.marks,info)
	child_texture = image_texture(event.child_pixels,child_info)
	poses = event.poses
	queue_redraw()

func fit(): auto_fit = true; pan = Vector2.ZERO; queue_redraw()
func actual(): auto_fit = false; zoom = 1.0; pan = Vector2.ZERO; queue_redraw()
func zoom_by(factor: float, at: Vector2 = Vector2(-1,-1)):
	if at.x < 0: at = size/2
	auto_fit = false
	var next = clampf(zoom*factor,0.015625,128)
	pan = (pan+size/2-at)*next/zoom-size/2+at
	zoom = next; queue_redraw()

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: zoom_by(1.25,event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: zoom_by(0.8,event.position)
		elif event.button_index in [MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_LEFT]: dragging = event.pressed
	elif event is InputEventMouseMotion and dragging: pan += event.relative; auto_fit = false; queue_redraw()
	elif event is InputEventScreenDrag: pan += event.relative; auto_fit = false; queue_redraw()
	elif event is InputEventMagnifyGesture: zoom_by(event.factor,event.position)

func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color(background_color,1.0) if background_mode == 1 else Color("141b25"))
	if background_mode == 0:
		for y in range(0,int(size.y),20):
			for x in range(0,int(size.x),20):
				if (x/20+y/20)%2: draw_rect(Rect2(x,y,20,20),Color("192331"))
	var font = get_theme_default_font()
	if info.is_empty():
		draw_string(font,Vector2(28,size.y/2-14),"PAPNG · PNG · APNG",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("c8dfdf"))
		draw_string(font,Vector2(28,size.y/2+22),"파일을 열거나 이곳으로 끌어 놓으세요.",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("8dabb9"))
		return
	var dimensions = Vector2(info.width,info.height)
	if auto_fit:
		zoom = minf((size.x-64)/dimensions.x,(size.y-64)/dimensions.y)
		if zoom >= 1: zoom = maxf(1,floor(zoom))
		zoom = clampf(zoom,0.015625,128)
	origin = (size-dimensions*zoom)/2+pan
	draw_reference()
	if texture != null: draw_texture_rect(texture,Rect2(origin,dimensions*zoom),false)
	if highlight and mark_texture != null:
		draw_rect(Rect2(origin,dimensions*zoom),Color(0,0,0,0.4))
		draw_texture_rect(mark_texture,Rect2(origin,dimensions*zoom),false,Color(1,1,1,0.8))
	if child_texture != null and socket_index < poses.size():
		var pose = poses[socket_index]
		var pivot = child_info.hints.get("pivot",[0,0])
		draw_set_transform(origin+Vector2(pose[0],pose[1])*zoom,deg_to_rad(pose[2]),Vector2.ONE*zoom)
		draw_texture_rect(child_texture,Rect2(-Vector2(pivot[0],pivot[1]),Vector2(child_info.width,child_info.height)),false)
		draw_set_transform(Vector2.ZERO)
	if hints:
		draw_rect(Rect2(origin,dimensions*zoom),Color("98bdf7"),false,1)
		if info.hints.has("bbox"):
			var box = info.hints.bbox
			draw_rect(Rect2(origin+Vector2(box[0],box[1])*zoom,Vector2(box[2],box[3])*zoom),Color("80edc1"),false,2)
			label_at(origin+Vector2(box[0],box[1])*zoom,"바운딩 박스",Color("80edc1"))
		if info.hints.has("pivot"):
			var pivot = info.hints.pivot
			marker(origin+Vector2(pivot[0],pivot[1])*zoom,"pivot (%s, %s)" % pivot,Color("ffd875"))
		var text = "캔버스 %d × %d" % [info.width,info.height]
		if info.hints.has("display"): text += " · 출력 %d × %d" % info.hints.display
		if info.hints.has("scale"): text += " · 픽셀 배수 %s" % info.hints.scale
		label_at(Vector2(12,22),text,Color("98bdf7"))
	if sockets:
		for i in poses.size():
			var pose = poses[i]
			var p = origin+Vector2(pose[0],pose[1])*zoom
			var color = Color("ff9dd6") if i == socket_index else Color("c6b9fa")
			marker(p,info.sockets[i],color)
			draw_line(p,p+Vector2(22,0).rotated(deg_to_rad(pose[2])),color,2,true)

func label_at(point: Vector2, text: String, color: Color):
	var font = get_theme_default_font()
	var at = point+Vector2(8,-8)
	draw_string_outline(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,15,4,Color("111820"))
	draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,15,color)
func marker(p: Vector2, text: String, color: Color):
	draw_arc(p,6,0,TAU,24,Color("111820"),5,true)
	draw_arc(p,6,0,TAU,24,color,2,true)
	draw_line(p-Vector2(10,0),p+Vector2(10,0),color,1,true)
	draw_line(p-Vector2(0,10),p+Vector2(0,10),color,1,true)
	label_at(p,text,color)
