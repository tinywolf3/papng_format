extends RefCounted
const Doc = preload("res://core/document.gd")
const MemoryDoc = preload("res://core/memory_document.gd")
const Player = preload("res://core/player.gd")
const Writer = preload("res://core/writer.gd")
const Metadata = preload("res://core/metadata_edit.gd")
const Parser = preload("res://core/json5.gd")
const Bin = preload("res://core/binary.gd")
const MAX_BYTES = 256*1024*1024
signal changed
var width = 32
var height = 32
var frames: Array = []
var selected = 0
var plays = 0
var hints: Dictionary = {}
var mask_count = 0
var distributions: Array = [{"kind":0,"valid":true,"items":[]}]
var metadata_text = "{schema_version: 1}"
var ancillary: Array = []
var path = ""
var error = ""
var warnings: Array = []
var undo_stack: Array = []
var redo_stack: Array = []
var before: Dictionary = {}
var action_name = ""
var touched = false
var revision = 0
var saved_revision = 0
var serial = 0
var history_bytes = 0
var preview_player
var runtime_doc

func _init(): new_document(32,32)
func blank(w: int, h: int) -> Dictionary:
	var rgba = PackedByteArray(); rgba.resize(w*h*4)
	return {"width":w,"height":h,"x":0,"y":0,"num":1,"den":10,"dispose":0,"blend":0,"rgba":rgba,"mask":PackedByteArray(),"control":{}}
func new_document(w: int, h: int):
	width = w; height = h; frames = [blank(w,h)]; selected = 0; path = ""; plays = 0
	hints = {}; mask_count = 0; distributions = [{"kind":0,"valid":true,"items":[]}]
	metadata_text = "{schema_version: 1}"; ancillary = []; warnings = []; error = ""
	reset_history(); invalidate()
func reset_history():
	undo_stack = []; redo_stack = []; before = {}; revision = 0; serial = 0; saved_revision = 0; history_bytes = 0
func dirty() -> bool: return revision != saved_revision or touched
func state() -> Dictionary:
	return {"width":width,"height":height,"frames":frames.duplicate(true),"selected":selected,"plays":plays,"hints":hints.duplicate(true),"mask_count":mask_count,"distributions":distributions.duplicate(true),"metadata_text":metadata_text,"revision":revision}
func restore(s: Dictionary):
	for key in s: set(key,s[key])
	touched = false; invalidate(); changed.emit()
func state_bytes(s: Dictionary) -> int:
	var count = s.metadata_text.length()*4+1024
	for f in s.frames: count += f.rgba.size()+f.mask.size()+256
	return count
func begin(label: String):
	if not before.is_empty(): return
	before = state(); action_name = label; touched = false
func touch(): touched = true; invalidate(); changed.emit()
func commit():
	if before.is_empty(): return
	if touched:
		undo_stack.append({"name":action_name,"state":before}); history_bytes += state_bytes(before)
		redo_stack.clear(); serial += 1; revision = serial
		while undo_stack.size()>32 or (history_bytes>128*1024*1024 and undo_stack.size()>1): history_bytes -= state_bytes(undo_stack.pop_front().state)
	before = {}; touched = false; changed.emit()
func cancel():
	if before.is_empty(): return
	var previous = before; before = {}; restore(previous)
func perform(label: String, action: Callable):
	begin(label); action.call(); commit()
func undo():
	if not before.is_empty(): cancel(); return
	if undo_stack.is_empty(): return
	var step = undo_stack.pop_back(); history_bytes -= state_bytes(step.state)
	redo_stack.append({"name":step.name,"state":state()}); restore(step.state)
func redo():
	if redo_stack.is_empty(): return
	var step = redo_stack.pop_back()
	undo_stack.append({"name":step.name,"state":state()}); history_bytes += state_bytes(undo_stack[-1].state)
	restore(step.state)
func invalidate(): preview_player = null; runtime_doc = null
func metadata() -> Dictionary:
	var p = Parser.new(); var obj = p.parse(metadata_text)
	return obj if p.error.is_empty() and obj is Dictionary else {}
func put_metadata(key: String, value: Variant):
	metadata_text = Metadata.set_member(metadata_text,key,value); touch()
func runtime():
	if runtime_doc != null: return runtime_doc
	var d = MemoryDoc.new()
	d.width = width; d.height = height; d.frames = frames; d.plays = plays; d.mask_count = mask_count; d.distributions = distributions
	d.hints = hints; d.controls = {}
	for i in frames.size():
		if not frames[i].control.is_empty(): d.controls[i] = [frames[i].control]
	if not metadata_text.is_empty(): d.parse_texts(["PAPNG.Metadata".to_utf8_buffer()+PackedByteArray([0,0,0,0,0])+metadata_text.to_utf8_buffer()])
	runtime_doc = d
	return d
func composite(index: int) -> PackedByteArray:
	if preview_player == null: preview_player = Player.new(runtime())
	preview_player.seek_canvas(index)
	return preview_player.state.get("pixels",PackedByteArray())
func image(index: int) -> Image:
	return Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,composite(index))
func source_image(index: int) -> Image:
	var f = frames[index]
	return Image.create_from_data(f.width,f.height,false,Image.FORMAT_RGBA8,f.rgba)
func frame_rect() -> Rect2i:
	var f = frames[selected]; return Rect2i(f.x,f.y,f.width,f.height)
func pixel_at(point: Vector2i) -> Dictionary:
	if not frame_rect().has_point(point): return {}
	var f = frames[selected]; var at = ((point.y-f.y)*f.width+point.x-f.x)*4
	var mask = -1
	if not f.mask.is_empty() and f.mask[at/2] & 0x80: mask = ((f.mask[at/2]<<8)|f.mask[at/2+1])&0x7fff
	return {"rgba":f.rgba.slice(at,at+4),"mask":mask}
func set_pixel(point: Vector2i, color: PackedByteArray, mask: int = -2) -> bool:
	if not frame_rect().has_point(point): return false
	var f = frames[selected]; var at = ((point.y-f.y)*f.width+point.x-f.x)*4
	var modified = false
	if color.size() == 4:
		for c in 4:
			if f.rgba[at+c] != color[c]: f.rgba[at+c] = color[c]; modified = true
	if mask != -2:
		if f.mask.is_empty(): f.mask.resize(f.width*f.height*2)
		var word = 0 if mask < 0 else 0x8000|mask
		if f.mask[at/2] != word>>8 or f.mask[at/2+1] != (word&255):
			f.mask[at/2] = word>>8; f.mask[at/2+1] = word&255; modified = true
	if modified: touched = true; invalidate()
	return modified
func flood(point: Vector2i, color: PackedByteArray, mask: int = -2, bounds: Rect2i = Rect2i()):
	var original = pixel_at(point)
	if original.is_empty(): return
	var rect = frame_rect() if not bounds.has_area() else frame_rect().intersection(bounds)
	if not rect.has_point(point): return
	var visited = PackedByteArray(); visited.resize(rect.size.x*rect.size.y)
	var queue: Array[Vector2i] = [point]
	var cursor = 0
	while cursor < queue.size():
		var p = queue[cursor]; cursor += 1
		if not rect.has_point(p): continue
		var key = (p.y-rect.position.y)*rect.size.x+p.x-rect.position.x
		if visited[key]: continue
		visited[key] = 1
		var value = pixel_at(p)
		if value.rgba != original.rgba or (mask != -2 and value.mask != original.mask): continue
		set_pixel(p,color,mask)
		for dir in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]: queue.append(p+dir)
	changed.emit()
func copy_region(rect: Rect2i) -> Dictionary:
	rect = rect.intersection(frame_rect())
	if not rect.has_area(): return {}
	var rgba = PackedByteArray(); var mask = PackedByteArray(); rgba.resize(rect.size.x*rect.size.y*4); mask.resize(rect.size.x*rect.size.y*2)
	for y in rect.size.y:
		for x in rect.size.x:
			var p = pixel_at(rect.position+Vector2i(x,y)); var at = (y*rect.size.x+x)*4
			for c in 4: rgba[at+c] = p.rgba[c]
			var word = 0 if p.mask < 0 else 0x8000|p.mask
			mask[at/2] = word>>8; mask[at/2+1] = word&255
	return {"width":rect.size.x,"height":rect.size.y,"rgba":rgba,"mask":mask}
func paste(data: Dictionary, position: Vector2i, over: bool = true):
	for y in data.height:
		for x in data.width:
			var at = (y*data.width+x)*4; var color = data.rgba.slice(at,at+4); var point = position+Vector2i(x,y)
			var dest = pixel_at(point)
			if dest.is_empty() or (over and color[3] == 0): continue
			if over and color[3] < 255:
				var sa = color[3]/255.0; var da = dest.rgba[3]/255.0; var a = sa+da*(1-sa)
				for c in 3: color[c] = roundi((color[c]*sa+dest.rgba[c]*da*(1-sa))/a)
				color[3] = roundi(a*255)
			var mask = -1
			if data.has("mask") and not data.mask.is_empty() and data.mask[at/2]&0x80:
				mask = ((data.mask[at/2]<<8)|data.mask[at/2+1])&0x7fff
				mask_count = maxi(mask_count,mask+1)
			set_pixel(point,color,mask)
	changed.emit()
func load_file(file_path: String, cancelled: Callable = Callable()) -> bool:
	var doc = Doc.new()
	if not doc.load_file(file_path,cancelled): error = doc.error; return false
	var loaded = []; var total = 0
	for i in doc.frames.size():
		if cancelled.is_valid() and cancelled.call(): error = "불러오기 취소"; return false
		var f = doc.frames[i].duplicate(true)
		f.rgba = doc.decode(i); f.mask = doc.mask(i); f.erase("data"); f.control = {}
		if not doc.error.is_empty(): error = doc.error; return false
		total += f.rgba.size()+f.mask.size()
		if total > MAX_BYTES: error = "편집 이미지가 256 MiB 작업 예산을 초과합니다"; return false
		loaded.append(f)
	var player = Player.new(doc)
	for i in doc.controls:
		var c = player.resolve(i)
		loaded[i].control = c.duplicate(true) if c.type >= 0 else {"type":0,"valid":true,"values":[1,100]}
	width = doc.width; height = doc.height; frames = loaded; plays = doc.plays; hints = doc.hints.duplicate(true); mask_count = doc.mask_count
	distributions = doc.distributions.duplicate(true)
	for d in distributions:
		if not d.get("valid",true): d.kind = 0; d.valid = true; d.items = []
	metadata_text = doc.metadata_text if not doc.metadata_text.is_empty() else "{schema_version: 1}"
	ancillary = []
	var reader = Bin.new(FileAccess.get_file_as_bytes(file_path)); reader.pos = 8
	while reader.pos < reader.data.size():
		var count = reader.u(4); var name = reader.take(4).get_string_from_ascii(); var data = reader.take(count); reader.u(4)
		if name.length() == 4 and name[0] == name[0].to_lower() and name[3] == name[3].to_lower() and name != "iTXt": ancillary.append({"name":name,"data":data})
		elif name == "iTXt" and not data.slice(0,15).get_string_from_ascii().begins_with("PAPNG.Metadata"): ancillary.append({"name":name,"data":data})
	selected = 0; path = file_path; warnings = doc.warnings.duplicate(); error = ""; reset_history(); invalidate(); repair_metadata()
	return true
func repair_metadata():
	# Readers recover optional metadata, but form controls must receive only valid values.
	var d=runtime()
	if d.warnings.is_empty(): return
	var original=metadata()
	if original.has("clips"):
		var entries=[]
		for c in d.clips: entries.append({"id":c.id,"name":c.name,"start_frame":c.start,"end_frame":c.end,"play_count":c.plays})
		metadata_text=Metadata.set_member(metadata_text,"clips",entries)
	if original.has("mask_groups"):
		var entries=[]
		for g in d.groups: entries.append({"id":g.id,"name":g.name,"palette_indices":g.indices})
		metadata_text=Metadata.set_member(metadata_text,"mask_groups",entries)
	if original.has("sockets"):
		var sockets={"definitions":[],"frames":[]}
		if not d.sockets.is_empty():
			for name in d.sockets.names: sockets.definitions.append({"name":name})
			for index in d.sockets.keys: sockets.frames.append({"frame_index":index,"positions":d.sockets.records[index]})
		metadata_text=Metadata.set_member(metadata_text,"sockets",sockets)
	invalidate()

func validate() -> String:
	if width < 1 or height < 1 or width*height*4>Doc.LIMIT: return "캔버스 크기가 처리 범위를 벗어납니다"
	if frames.is_empty() or mask_count < 0 or mask_count > 32768 or distributions.size()>256: return "프레임·마스크·분포 개수 오류"
	var total_bytes=0
	for f in frames:
		total_bytes+=f.rgba.size()+f.mask.size()
		if total_bytes>MAX_BYTES: return "편집 데이터가 256 MiB 작업 예산을 초과합니다"
		if f.width<1 or f.height<1 or f.x<0 or f.y<0 or f.x+f.width>width or f.y+f.height>height: return "프레임 영역이 캔버스를 벗어납니다"
		if f.rgba.size()!=f.width*f.height*4 or (not f.mask.is_empty() and f.mask.size()!=f.width*f.height*2): return "픽셀·마스크 크기 오류"
		for pos in range(0,f.mask.size(),2):
			var word = (f.mask[pos]<<8)|f.mask[pos+1]
			if word != 0 and (not word&0x8000 or (word&0x7fff)>=mask_count): return "마스크 번호 범위 오류"
		if f.num<0 or f.num>65535 or f.den<0 or f.den>65535 or f.dispose<0 or f.dispose>2 or f.blend<0 or f.blend>1: return "프레임 지연·합성 값 오류"
	for key in hints:
		var v=hints[key]
		if key=="scale":
			if v<1 or v>4294967295: return "픽셀 배수는 양의 uint32 값이어야 합니다"
		elif key in ["display","bbox","pivot"]:
			if v.size()!=(4 if key=="bbox" else 2): return "힌트 항목 개수 오류"
			for value in v:
				if value<(-2147483648 if key=="pivot" else 0) or value>(2147483647 if key=="pivot" else 4294967295): return "힌트 값 범위 오류"
			if key=="display" and (v[0]==0 or v[1]==0): return "출력 크기는 양수여야 합니다"
			if key=="bbox" and (v[2]==0 or v[3]==0 or v[0]+v[2]>width or v[1]+v[3]>height): return "바운딩 박스는 캔버스 안에 있어야 합니다"
	for d in distributions:
		if d.kind<0 or d.kind>4: return "지원하지 않는 분포"
		if d.kind==4:
			if d.items.is_empty() or d.items.size()>4194302: return "가중치 항목 개수 오류"
			var total=0
			for item in d.items:
				if item.value < -8388608 or item.value > 8388607 or item.weight<0 or item.weight>255: return "가중치 항목은 int24 값과 0~255 가중치여야 합니다"
				total += item.weight
			if total==0: return "양수 가중치가 하나 이상 필요합니다"
	var parser = Parser.new(); var obj = parser.parse(metadata_text)
	if not parser.error.is_empty() or not obj is Dictionary or obj.get("schema_version")!=1: return "JSON5 메타데이터 오류: "+parser.error
	var d = runtime()
	for i in frames.size():
		var c=frames[i].control
		if not c.is_empty():
			if c.type<0 or c.type>5 or c.values.size()!=[2,4,1,1,3,3][c.type]: return "프레임 제어 구조 오류"
			for j in c.values.size():
				var value=c.values[j]; var low=0; var high=4294967295
				if c.type in [0,1]: high=255 if c.type==1 and j==3 else 65535
				elif c.type in [2,4] and j<2: low=-2147483648; high=2147483647
				if c.type in [4,5] and j==2: high=255
				if value<low or value>high: return "프레임 제어 값의 저장 범위를 벗어납니다"
	var p = Player.new(d)
	for i in frames.size():
		var c=frames[i].control
		if not c.is_empty() and (not p.valid_control(c,i)): return "프레임 %d의 제어 대상 또는 분포가 올바르지 않습니다" % i
	if not d.warnings.is_empty(): return "메타데이터: "+"; ".join(d.warnings)
	return ""
func save_file(file_path: String) -> bool:
	error = validate()
	if not error.is_empty(): return false
	var bytes = Writer.encode(self)
	var verify = Doc.new()
	if not verify.load_bytes(bytes) or not verify.warnings.is_empty(): error = "저장 데이터 검증 실패: "+verify.error+"; ".join(verify.warnings); return false
	var temporary = file_path+".papng-editor-"+str(Time.get_ticks_usec())+".tmp"
	var file = FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: error = "저장 위치에 쓸 수 없습니다"; return false
	file.store_buffer(bytes); file.flush(); var failure=file.get_error(); file.close()
	if failure != OK or DirAccess.rename_absolute(temporary,file_path)!=OK:
		DirAccess.remove_absolute(temporary); error = "파일 저장을 완료하지 못했습니다. 원본은 유지됩니다"; return false
	path = file_path; saved_revision = revision; return true
