extends Control
signal cursor_changed(point: Vector2i, data: Dictionary)
signal zoom_changed(value: int)
signal picked(color: Color)
signal socket_placed(point: Vector2i)
signal message(text: String)
signal selection_changed
var model
var tool = "pencil"
var color = Color("ebbb71")
var brush = 1
var mask_index = 0
var zoom = 12
var pan = Vector2.ZERO
var origin = Vector2.ZERO
var cursor = Vector2i(-1,-1)
var has_cursor = false
var show_grid = true
var show_cross = true
var show_mask = false
var show_hints = true
var show_sockets = true
var onion = false
var selection = Rect2i()
var texture: ImageTexture
var ghost: ImageTexture
var mask_texture: ImageTexture
var playback_texture: ImageTexture
var playback_marks: ImageTexture
var playback_index = -1
var playing = false
var floating: Dictionary = {}
var floating_texture: ImageTexture
var floating_position = Vector2i.ZERO
var replace_paste = false
var dragging = false
var panning = false
var start = Vector2i.ZERO
var previous = Vector2i.ZERO
var drag_start = Vector2i.ZERO
var selected_socket = 0
var hue_offsets: Dictionary = {}
var accessory_texture: ImageTexture
var accessory_pivot=Vector2.ZERO
# Editor-only background. Coordinates are in document pixels, never viewport pixels.
var background_mode=0 # 0 checkerboard, 1 solid color
var background_color=Color("25303b")
var reference_texture: ImageTexture
var reference_position=Vector2.ZERO
var reference_scale=1.0
var reference_opacity=0.5
var reference_visible=true

func set_reference(image: Image):
	if image==null or image.is_empty(): return
	reference_texture=ImageTexture.create_from_image(image)
	reference_visible=true; reference_opacity=0.5; fit_reference()
func clear_reference():
	reference_texture=null; reference_position=Vector2.ZERO; reference_scale=1.0
	reference_opacity=0.5; reference_visible=true; queue_redraw()
func fit_reference():
	if reference_texture==null or model==null: return
	var dimensions=Vector2(model.width,model.height)
	var image_size=reference_texture.get_size()
	reference_scale=minf(dimensions.x/image_size.x,dimensions.y/image_size.y)
	reference_position=(dimensions-image_size*reference_scale)/2; queue_redraw()
func draw_background(canvas_rect: Rect2):
	var visible=canvas_rect.intersection(Rect2(Vector2.ZERO,size))
	if not visible.has_area(): return
	if background_mode==1:
		draw_rect(visible,Color(background_color,1.0))
	else:
		draw_rect(visible,Color("25303b"))
		# The checkerboard follows the same document origin and zoom as pixels.
		var cell=8.0*zoom
		for y in range(floori((visible.position.y-origin.y)/cell),ceili((visible.end.y-origin.y)/cell)):
			for x in range(floori((visible.position.x-origin.x)/cell),ceili((visible.end.x-origin.x)/cell)):
				if (x+y)%2: draw_rect(Rect2(origin+Vector2(x,y)*cell,Vector2.ONE*cell).intersection(visible),Color("35434e"))
	if reference_texture==null or not reference_visible or reference_opacity<=0: return
	var scale=reference_scale*zoom
	var image_rect=Rect2(origin+reference_position*zoom,reference_texture.get_size()*scale)
	var clipped=image_rect.intersection(visible)
	if not clipped.has_area(): return
	# Clip both source and destination: a large/offset reference cannot cover the workspace.
	var source=Rect2((clipped.position-image_rect.position)/scale,clipped.size/scale)
	draw_texture_rect_region(reference_texture,clipped,source,Color(1,1,1,reference_opacity))

func _ready():
	clip_contents=true; mouse_filter=Control.MOUSE_FILTER_STOP; focus_mode=Control.FOCUS_ALL
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)
func update_origin(): origin=((size-Vector2(model.width,model.height)*zoom)/2+pan).floor()
func pixel(position: Vector2) -> Vector2i:
	update_origin(); return Vector2i(((position-origin)/zoom).floor())
func refresh():
	if model==null: return
	var f=model.frames[model.selected]
	var source=f.rgba.duplicate()
	if not hue_offsets.is_empty():
		for pos in range(0,f.mask.size(),2):
			if f.mask[pos]&0x80:
				var offset=model.Player.adjustment(hue_offsets.get(((f.mask[pos]<<8)|f.mask[pos+1])&0x7fff,0))
				if offset!=Vector3.ZERO:
					var at=pos*2; var rgb=model.Player.hue(source[at],source[at+1],source[at+2],offset.x,offset.y,offset.z)
					for c in 3: source[at+c]=rgb[c]
	texture=ImageTexture.create_from_image(Image.create_from_data(f.width,f.height,false,Image.FORMAT_RGBA8,source))
	ghost=ImageTexture.create_from_image(model.image(model.selected-1)) if onion and model.selected>0 else null
	mask_texture=null
	if show_mask and not f.mask.is_empty():
		var rgba=PackedByteArray(); rgba.resize(f.width*f.height*4)
		for pos in range(0,f.mask.size(),2):
			if f.mask[pos]&0x80:
				var id=((f.mask[pos]<<8)|f.mask[pos+1])&0x7fff
				var tint=Color.from_hsv(fposmod(id*0.618,1),0.65,1)
				for c in 3: rgba[pos*2+c]=roundi(tint[c]*255)
				rgba[pos*2+3]=180 if id==mask_index else 70
		mask_texture=ImageTexture.create_from_image(Image.create_from_data(f.width,f.height,false,Image.FORMAT_RGBA8,rgba))
	if has_cursor: cursor_changed.emit(cursor,model.pixel_at(cursor))
	queue_redraw()
func fit():
	if model==null: return
	zoom=clampi(int(minf((size.x-50)/model.width,(size.y-50)/model.height)),1,128); pan=Vector2.ZERO
	zoom_changed.emit(zoom); queue_redraw()
func set_zoom(value: int, at: Vector2 = Vector2(-1,-1)):
	if at.x<0: at=size/2
	update_origin(); var anchor=(at-origin)/zoom
	zoom=clampi(value,1,128)
	pan=at-anchor*zoom-(size-Vector2(model.width,model.height)*zoom)/2
	zoom_changed.emit(zoom); queue_redraw()
func stop_gesture():
	if dragging and tool not in ["select","line","rect"] and floating.is_empty(): model.commit()
	dragging=false; panning=false
func stamp(point: Vector2i, erase: bool = false):
	var rgba=PackedByteArray() if tool=="mask" else PackedByteArray([0,0,0,0]) if tool=="erase" else PackedByteArray([color.r8,color.g8,color.b8,color.a8])
	var mask=-1 if tool=="erase" or (tool=="mask" and erase) else mask_index if tool=="mask" else -2
	if mask>=model.mask_count: message.emit("마스크 탭에서 사용할 마스크를 먼저 추가하세요."); return
	for y in brush:
		for x in brush:
			var p=point+Vector2i(x-brush/2,y-brush/2)
			if not selection.has_area() or selection.has_point(p): model.set_pixel(p,rgba,mask)
func stroke(a: Vector2i, b: Vector2i, erase: bool = false):
	var dx=absi(b.x-a.x); var dy=-absi(b.y-a.y); var sx=1 if a.x<b.x else -1; var sy=1 if a.y<b.y else -1
	var error=dx+dy; var point=a
	while true:
		stamp(point,erase)
		if point==b: break
		var twice=2*error
		if twice>=dy: error+=dy; point.x+=sx
		if twice<=dx: error+=dx; point.y+=sy
func copy_selection(cut: bool = false) -> Dictionary:
	var data=model.copy_region(selection if selection.has_area() else model.frame_rect())
	if cut and not data.is_empty():
		model.begin("잘라내기")
		var rect=selection.intersection(model.frame_rect()) if selection.has_area() else model.frame_rect()
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x): model.set_pixel(Vector2i(x,y),PackedByteArray([0,0,0,0]),-1)
		model.changed.emit(); model.commit()
	return data
func clear_selection():
	var rect=selection.intersection(model.frame_rect()) if selection.has_area() else model.frame_rect()
	model.begin("선택 영역 지우기")
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x): model.set_pixel(Vector2i(x,y),PackedByteArray([0,0,0,0]),-1)
	model.changed.emit(); model.commit()
func start_paste(data: Dictionary):
	stop_gesture(); floating=data.duplicate(true)
	floating_texture=ImageTexture.create_from_image(Image.create_from_data(data.width,data.height,false,Image.FORMAT_RGBA8,data.rgba))
	floating_position=selection.position if selection.has_area() else model.frame_rect().position
	message.emit("드래그로 배치 · Enter로 붙이기 · Esc로 취소 · 덮어쓰기 옵션에서 투명 픽셀 처리 선택")
	queue_redraw()
func apply_paste():
	if floating.is_empty(): return
	if not Rect2i(floating_position,Vector2i(floating.width,floating.height)).intersects(model.frame_rect()): message.emit("붙일 영역이 현재 프레임 밖입니다."); return
	model.begin("붙여넣기"); model.paste(floating,floating_position,not replace_paste); model.commit()
	floating={}; floating_texture=null; queue_redraw()
func cancel_paste(): floating={}; floating_texture=null; queue_redraw()
func _gui_input(event):
	if model==null: return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			set_zoom(zoom+(1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1),event.position); accept_event(); return
		if event.button_index==MOUSE_BUTTON_MIDDLE or (event.button_index==MOUSE_BUTTON_LEFT and Input.is_physical_key_pressed(KEY_SPACE)):
			panning=event.pressed; accept_event(); return
		if event.button_index!=MOUSE_BUTTON_LEFT: return
		grab_focus()
		if playing: message.emit("재생을 멈춘 뒤 편집하세요."); return
		var point=pixel(event.position)
		if event.pressed:
			start=point; previous=point; dragging=true
			if not floating.is_empty(): drag_start=point-floating_position; return
			if tool=="select": selection=Rect2i(point,Vector2i.ONE); selection_changed.emit()
			elif tool=="pick":
				var p=model.pixel_at(point)
				if not p.is_empty(): picked.emit(Color8(p.rgba[0],p.rgba[1],p.rgba[2],p.rgba[3]))
				dragging=false
			elif tool=="socket": socket_placed.emit(point); dragging=false
			elif tool=="fill":
				model.begin("영역 채우기"); model.flood(point,PackedByteArray([color.r8,color.g8,color.b8,color.a8]),-2,selection); model.commit(); dragging=false
			elif tool not in ["line","rect"]:
				model.begin("마스크 그리기" if tool=="mask" else "픽셀 그리기"); stamp(point,event.shift_pressed); model.changed.emit()
		elif dragging:
			if floating.is_empty():
				if tool in ["line","rect"]:
					model.begin("선 그리기" if tool=="line" else "사각형 그리기")
					if tool=="line": stroke(start,point)
					else:
						stroke(start,Vector2i(point.x,start.y)); stroke(Vector2i(point.x,start.y),point)
						stroke(point,Vector2i(start.x,point.y)); stroke(Vector2i(start.x,point.y),start)
					model.changed.emit()
				model.commit()
			dragging=false
		queue_redraw(); accept_event()
	elif event is InputEventMouseMotion:
		if panning: pan+=event.relative; queue_redraw(); accept_event(); return
		var point=pixel(event.position)
		cursor=point; has_cursor=Rect2i(0,0,model.width,model.height).has_point(point)
		cursor_changed.emit(point,model.pixel_at(point))
		if dragging and not playing:
			if not floating.is_empty(): floating_position=point-drag_start
			elif tool=="select": selection=Rect2i(start.min(point),(start-point).abs()+Vector2i.ONE).intersection(Rect2i(0,0,model.width,model.height)); selection_changed.emit()
			elif tool in ["pencil","erase","mask"]: stroke(previous,point,event.shift_pressed); model.changed.emit()
		previous=point; queue_redraw()
func label_at(point: Vector2, text: String, tint: Color):
	var font=get_theme_default_font()
	draw_string_outline(font,point,text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,3,Color("11161d"))
	draw_string(font,point,text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,tint)
func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color("11161d"))
	if model==null: return
	update_origin()
	var canvas=Rect2(origin,Vector2(model.width,model.height)*zoom)
	draw_background(canvas)
	if playing and playback_texture!=null:
		draw_texture_rect(playback_texture,canvas,false)
		if show_mask and playback_marks!=null: draw_texture_rect(playback_marks,canvas,false,Color(1,1,1,0.45))
	else:
		if ghost!=null: draw_texture_rect(ghost,canvas,false,Color(0.55,0.85,1,0.24))
		var f=model.frames[model.selected]; var frame_box=Rect2(origin+Vector2(f.x,f.y)*zoom,Vector2(f.width,f.height)*zoom)
		if texture!=null: draw_texture_rect(texture,frame_box,false)
		if mask_texture!=null: draw_texture_rect(mask_texture,frame_box,false)
		if f.width!=model.width or f.height!=model.height or f.x or f.y: draw_rect(frame_box,Color("d6a760"),false,2)
	if accessory_texture!=null:
		var poses=model.runtime().sockets_at(playback_index if playing else model.selected)
		if selected_socket>=0 and selected_socket<poses.size():
			var pose=poses[selected_socket]
			draw_set_transform(origin+Vector2(pose[0],pose[1])*zoom,deg_to_rad(pose[2]),Vector2.ONE*zoom)
			draw_texture(accessory_texture,-accessory_pivot); draw_set_transform(Vector2.ZERO)
	if floating_texture!=null: draw_texture_rect(floating_texture,Rect2(origin+Vector2(floating_position)*zoom,Vector2(floating.width,floating.height)*zoom),false,Color(1,1,1,0.8))
	if show_grid and zoom>=6:
		var from_x=maxi(0,int(-origin.x/zoom)); var to_x=mini(model.width,int((size.x-origin.x)/zoom)+1)
		var from_y=maxi(0,int(-origin.y/zoom)); var to_y=mini(model.height,int((size.y-origin.y)/zoom)+1)
		for x in range(from_x,to_x+1): draw_line(Vector2(origin.x+x*zoom,canvas.position.y),Vector2(origin.x+x*zoom,canvas.end.y),Color(0,0,0,0.18))
		for y in range(from_y,to_y+1): draw_line(Vector2(canvas.position.x,origin.y+y*zoom),Vector2(canvas.end.x,origin.y+y*zoom),Color(0,0,0,0.18))
	draw_rect(canvas,Color("74858f"),false,1)
	if selection.has_area(): draw_rect(Rect2(origin+Vector2(selection.position)*zoom,Vector2(selection.size)*zoom),Color("ffe6a6"),false,2)
	if dragging and floating.is_empty() and tool in ["line","rect"]:
		if tool=="line": draw_line(origin+(Vector2(start)+Vector2(0.5,0.5))*zoom,origin+(Vector2(cursor)+Vector2(0.5,0.5))*zoom,Color(1,1,1,0.8),2)
		else: draw_rect(Rect2(origin+Vector2(start.min(cursor))*zoom,Vector2((start-cursor).abs()+Vector2i.ONE)*zoom),Color.WHITE,false,2)
	if show_hints:
		if model.hints.has("bbox"):
			var b=model.hints.bbox; draw_rect(Rect2(origin+Vector2(b[0],b[1])*zoom,Vector2(b[2],b[3])*zoom),Color("80d9b4"),false,2)
		if model.hints.has("pivot"):
			var p=model.hints.pivot; var at=origin+Vector2(p[0],p[1])*zoom
			draw_circle(at,5,Color("ffd48a"),false,2); label_at(at+Vector2(8,-8),"pivot",Color("ffd48a"))
	if show_sockets:
		var doc=model.runtime(); var poses=doc.sockets_at(playback_index if playing else model.selected)
		for i in poses.size():
			var p=poses[i]; var at=origin+Vector2(p[0],p[1])*zoom; var tint=Color("f5a6d6") if i==selected_socket else Color("b8b5f4")
			draw_circle(at,5,tint,false,2); draw_line(at,at+Vector2(20,0).rotated(deg_to_rad(p[2])),tint,2)
			label_at(at+Vector2(8,-8),doc.sockets.names[i],tint)
	if show_cross and has_cursor:
		var at=origin+(Vector2(cursor)+Vector2(0.5,0.5))*zoom
		draw_line(Vector2(0,at.y),Vector2(size.x,at.y),Color(0,0,0,0.85),3)
		draw_line(Vector2(at.x,0),Vector2(at.x,size.y),Color(0,0,0,0.85),3)
		draw_line(Vector2(0,at.y),Vector2(size.x,at.y),Color(0.65,0.97,0.89,0.75),1)
		draw_line(Vector2(at.x,0),Vector2(at.x,size.y),Color(0.65,0.97,0.89,0.75),1)
		draw_rect(Rect2(origin+Vector2(cursor)*zoom,Vector2.ONE*zoom),Color("b5ffe9"),false,1)
