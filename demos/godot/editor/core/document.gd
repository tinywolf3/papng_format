extends RefCounted
const Bin = preload("res://core/binary.gd")
const Json5 = preload("res://core/json5.gd")
const SIGNATURE = [137,80,78,71,13,10,26,10]
const LIMIT = 128 * 1024 * 1024
var error = ""
var warnings: Array[String] = []
var width = 0
var height = 0
var plays = 0
var frames: Array = []
var mask_count = 0
var maps: Array = []
var bindings: Dictionary = {}
var distributions: Array = [{"kind":0,"valid":true}]
var controls: Dictionary = {}
var hints: Dictionary = {}
var clips: Array = []
var groups: Array = []
var sockets: Dictionary = {}
var metadata_text = ""
var source_kind = "PAPNG"
var header = PackedByteArray()
var color_chunks = PackedByteArray()
var mask_cache: Dictionary = {}
var mask_cache_bytes = 0
var cancel: Callable

func warn(message: String):
	if warnings.size() < 100 and not warnings.has(message): warnings.append(message)

func check(valid: bool, message: String) -> bool:
	if not valid and error.is_empty(): error = message
	return valid

func load_file(path: String, cancelled: Callable = Callable()) -> bool:
	cancel = cancelled
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return check(false,"파일을 열 수 없습니다: " + path)
	if file.get_length() > LIMIT: return check(false,"파일이 뷰어의 128 MiB 처리 예산을 초과합니다")
	return load_bytes(file.get_buffer(file.get_length()))

func load_bytes(bytes: PackedByteArray) -> bool:
	if not check(bytes.slice(0,8) == PackedByteArray(SIGNATURE),"PNG 시그니처가 없습니다"): return false
	var r = Bin.new(bytes)
	r.pos = 8
	var count = 0
	var sequence = 0
	var idat = false
	var ended_idat = false
	var ended = false
	var current: Dictionary = {}
	var first_data = PackedByteArray()
	var ex: Array = []
	var md: Array = []
	var texts: Array = []
	while r.pos < bytes.size() and error.is_empty():
		if cancel.is_valid() and cancel.call(): return check(false,"불러오기 취소")
		var size = r.u(4)
		var name_bytes = r.take(4)
		var name = name_bytes.get_string_from_ascii()
		var data = r.take(size)
		var expected_crc = r.u(4)
		if not check(r.error.is_empty() and size <= 0x7fffffff,"잘린 PNG 청크"): break
		var valid_name = RegEx.create_from_string("^[A-Za-z]{2}[A-Z][A-Za-z]$").search(name) != null
		if not check(valid_name and (width > 0 or name == "IHDR"),"PNG 청크 순서·이름 오류"): break
		var valid = Bin.crc(name_bytes + data) == expected_crc
		if not check(valid or name in ["paEX","paMD","iTXt"],name + " CRC 오류"): break
		if idat and name != "IDAT": ended_idat = true
		var p = Bin.new(data)
		match name:
			"IHDR":
				if not check(width == 0 and size == 13,"IHDR 오류"): break
				width = p.u(4); height = p.u(4); header = data
				if not check(width > 0 and height > 0 and width <= LIMIT / 4 and height <= LIMIT / (width * 4),"캔버스가 뷰어의 128 MiB 처리 예산을 초과합니다"): break
			"acTL":
				if not check(count == 0 and not idat and size == 8,"acTL 오류"): break
				count = p.u(4); plays = p.u(4)
				check(count > 0,"빈 애니메이션")
			"fcTL":
				if not check(count > 0 and size == 26 and p.u(4) == sequence,"fcTL 순서 오류"): break
				sequence += 1
				if not check(current.is_empty() or not current.data.is_empty(),"프레임 데이터 누락"): break
				current = {"width":p.u(4),"height":p.u(4),"x":p.u(4),"y":p.u(4),"num":p.u(2),"den":p.u(2),"dispose":p.u(1),"blend":p.u(1),"data":PackedByteArray(),"idat":not idat}
				if not check(current.width > 0 and current.height > 0 and current.width + current.x <= width and current.height + current.y <= height and current.dispose <= 2 and current.blend <= 1,"프레임 범위·합성 연산 오류"): break
				if not idat and not check(frames.is_empty() and current.width == width and current.height == height and current.x == 0 and current.y == 0,"기본 프레임 크기 오류"): break
				frames.append(current)
			"IDAT":
				if not check(not ended_idat,"IDAT 순서 오류"): break
				idat = true
				if not current.is_empty(): current.data.append_array(data)
				elif count == 0: first_data.append_array(data)
			"fdAT":
				if not check(idat and not current.is_empty() and not current.idat and size >= 4 and p.u(4) == sequence,"fdAT 순서 오류"): break
				sequence += 1
				current.data.append_array(p.take(size - 4))
			"paEX": ex.append({"data":data,"valid":valid and not idat})
			"paMD": md.append({"data":data,"valid":valid and not idat and ex.size() == 1})
			"iTXt":
				if valid: texts.append(data)
				else: warn("iTXt CRC 오류: 메타데이터 무시")
			"PLTE", "tRNS": color_chunks.append_array(Bin.chunk(name,data))
			"IEND":
				check(size == 0 and idat and r.pos == bytes.size(),"IEND 오류")
				ended = true
				break
			_:
				check(name[0].to_lower() == name[0],"알 수 없는 필수 청크: " + name)
	if not error.is_empty(): return false
	if not check(ended and frames.size() == count and (count == 0 or not current.data.is_empty()),"종료·프레임 개수 오류"): return false
	var recognized: Array = ex.filter(func(e): return e.data.slice(0,8) == PackedByteArray([80,65,80,78,71,0,0,0]))
	if recognized.is_empty():
		if not ex.is_empty(): return check(false,"알 수 없는 PAPNG 식별자")
		source_kind = "PNG" if count == 0 else "APNG"
		if count == 0:
			frames.append({"width":width,"height":height,"x":0,"y":0,"num":1,"den":100,"dispose":0,"blend":0,"data":first_data})
			plays = 1
		for f in frames:
			if f.num == 0: f.num = 1; f.den = 100; warn("가져오기: 0 지연을 10 ms로 변환했습니다")
			elif f.den == 0: f.den = 100
	else:
		if not check(count > 0 and header[8] == 8 and header[9] == 6,"PAPNG에는 RGBA8 애니메이션이 필요합니다"): return false
		var e = recognized[0]
		var version = Bin.new(e.data)
		version.pos = 8
		if not check(e.data.size() >= 10 and version.u(2) == 1,"지원하지 않는 PAPNG 버전"): return false
		var usable = false
		if ex.size() != 1 or not e.valid: warn("paEX CRC·위치·중복 오류: 확장 무시")
		else: usable = parse_extension(e.data)
		if md.size() > 1 or md.any(func(m): return not m.valid): warn("paMD CRC·위치·중복 오류: 마스크 무시")
		elif md.size() == 1 and usable: parse_masks(md[0].data)
		parse_texts(texts)
	return true

func parse_extension(bytes: PackedByteArray) -> bool:
	var r = Bin.new(bytes)
	r.pos = 10
	var minor = r.u(2)
	var size = r.u(4)
	if bytes.size() < 56 or size < 56 or size > bytes.size() or (minor == 0 and size != 56):
		warn("paEX 헤더 오류: 확장 무시"); return false
	var flags = r.u(4)
	var dw = r.u(4); var dh = r.u(4)
	var bx = r.signed(4); var by = r.signed(4); var bw = r.u(4); var bh = r.u(4)
	var scale = r.u(4); var px = r.signed(4); var py = r.signed(4)
	if flags & 1 and dw > 0 and dh > 0: hints.display = [dw,dh]
	if flags & 2 and bx >= 0 and by >= 0 and bw > 0 and bh > 0 and bx + bw <= width and by + bh <= height: hints.bbox = [bx,by,bw,bh]
	if flags & 4 and scale > 0: hints.scale = scale
	if flags & 8: hints.pivot = [px,py]
	if minor > 0 or flags >> 4: warn("알 수 없는 확장 필드는 무시합니다")
	r.pos = size
	var masks = r.u(2)
	if masks <= 32768: mask_count = masks
	else: warn("마스크 개수 범위 오류")
	var count = r.u(1)
	for i in count:
		var kind = r.u(1); var length = r.u(3); var p = Bin.new(r.take(length))
		if not r.error.is_empty(): break
		var d = {"kind":kind,"valid":false,"items":[]}
		if kind <= 3: d.valid = length == 0
		elif kind == 4 and length >= 4:
			var n = p.u(4)
			if n > 0 and length == 4 + 4 * n:
				for j in n: d.items.append({"value":p.signed(3),"weight":p.u(1)})
				d.valid = d.items.any(func(item): return item.weight > 0)
		distributions.append(d)
		if not d.valid: warn("유효하지 않은 랜덤 분포")
	var control_count = r.u(4)
	for i in control_count:
		var frame = r.u(4); var kind = r.u(4); var length = r.u(4); var p = Bin.new(r.take(length))
		if not r.error.is_empty(): break
		var valid = kind < 6 and [4,7,4,4,9,9][kind] == length
		var values = []
		if valid:
			match kind:
				0: values = [p.u(2),p.u(2)]
				1: values = [p.u(2),p.u(2),p.u(2),p.u(1)]
				2: values = [p.signed(4)]
				3: values = [p.u(4)]
				4: values = [p.signed(4),p.signed(4),p.u(1)]
				5: values = [p.u(4),p.u(4),p.u(1)]
		if frame >= frames.size(): warn("존재하지 않는 프레임의 제어 무시"); continue
		if not controls.has(frame): controls[frame] = []
		else: warn("중복 제어: 첫 유효 레코드 사용")
		controls[frame].append({"type":kind,"values":values,"valid":valid})
	if not r.error.is_empty(): warn("paEX 본문 해석 중단: 검증한 앞부분 유지")
	elif r.pos != bytes.size(): warn("paEX 후행 데이터")
	return true

func parse_masks(bytes: PackedByteArray):
	var r = Bin.new(bytes)
	var count = r.u(4)
	for i in count:
		var w = r.u(4); var h = r.u(4); var n = r.u(4); var compressed = r.take(n)
		if not r.error.is_empty(): break
		maps.append({"width":w,"height":h,"data":compressed,"valid":w > 0 and h > 0 and w <= width and h <= height and n > 0})
	var n = r.u(4)
	for i in n:
		var f = r.u(4); var m = r.u(4)
		if not r.error.is_empty(): break
		if f >= frames.size() or m >= maps.size() or not maps[m].valid or maps[m].width != frames[f].width or maps[m].height != frames[f].height:
			warn("잘못된 마스크 참조 무시"); continue
		if bindings.has(f): warn("중복 마스크 참조 무시")
		else: bindings[f] = m
	if not r.error.is_empty(): warn("paMD 해석 중단: 검증한 앞부분 유지")
	elif r.pos != bytes.size(): warn("paMD 후행 데이터")

func mask(frame: int) -> PackedByteArray:
	if not bindings.has(frame): return PackedByteArray()
	var id = bindings[frame]
	if not maps[id].valid: return PackedByteArray()
	if mask_cache.has(id):
		var cached = mask_cache[id]
		mask_cache.erase(id); mask_cache[id] = cached
		return cached
	var m = maps[id]
	var expected = m.width * m.height * 2
	var bytes = Bin.inflate(m.data,expected)
	if bytes.size() != expected:
		m.valid = false; warn("마스크 압축·길이 오류: 원본색 유지"); return PackedByteArray()
	for p in range(0,bytes.size(),2):
		var word = (bytes[p] << 8) | bytes[p+1]
		if word != 0 and (not word & 0x8000 or (word & 0x7fff) >= mask_count):
			bytes[p] = 0; bytes[p+1] = 0; warn("마스크 인덱스·예약 비트 오류: 원본색 유지")
	if expected <= 16 * 1024 * 1024:
		while mask_cache_bytes + expected > 16 * 1024 * 1024:
			var key = mask_cache.keys()[0]; mask_cache_bytes -= mask_cache[key].size(); mask_cache.erase(key)
		mask_cache[id] = bytes; mask_cache_bytes += expected
	return bytes

func decode(frame: int) -> PackedByteArray:
	var f = frames[frame]
	var ihdr = Bin.be(f.width,4) + Bin.be(f.height,4) + header.slice(8)
	var png = PackedByteArray(SIGNATURE) + Bin.chunk("IHDR",ihdr) + color_chunks + Bin.chunk("IDAT",f.data) + Bin.chunk("IEND",PackedByteArray())
	var image = Image.new()
	if image.load_png_from_buffer(png) != OK:
		check(false,"PNG 프레임을 디코딩할 수 없습니다"); return PackedByteArray()
	image.convert(Image.FORMAT_RGBA8)
	return image.get_data()

static func finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func uint(value: Variant) -> bool:
	return finite(value) and value == floor(value) and value >= 0 and value <= 0xffffffff

func parse_texts(texts: Array):
	var seen = false
	for bytes in texts:
		var zero = bytes.find(0)
		if zero < 0 or bytes.slice(0,zero).get_string_from_ascii() != "PAPNG.Metadata": continue
		if seen:
			clips.clear(); groups.clear(); sockets.clear(); metadata_text = ""; warn("중복 PAPNG.Metadata: 무시"); return
		seen = true
		var r = Bin.new(bytes); r.pos = zero + 1
		var compression = r.u(1); var method = r.u(1)
		for i in 2:
			zero = bytes.find(0,r.pos)
			if zero < 0: r.error = "iTXt 구분자 오류"; break
			r.pos = zero + 1
		if compression > 1 or method != 0 or not r.error.is_empty(): warn("iTXt 구조 오류"); continue
		var raw = r.take(bytes.size()-r.pos)
		if compression: raw = Bin.inflate(raw,8*1024*1024)
		if raw.is_empty() or raw.size() > 8*1024*1024: warn("메타데이터 압축·처리 예산 오류"); continue
		var text = raw.get_string_from_utf8()
		if text.to_utf8_buffer() != raw: warn("메타데이터 UTF-8 오류"); continue
		var parser = Json5.new()
		var obj = parser.parse(text)
		if not parser.error.is_empty() or not obj is Dictionary or not uint(obj.get("schema_version")) or obj.schema_version != 1 or not obj.get("clips",[]) is Array or not obj.get("mask_groups",[]) is Array:
			warn("메타데이터 무시: " + parser.error); continue
		metadata_text = text
		for c in obj.get("clips",[]):
			if not c is Dictionary or not c.get("id") is String or c.id.is_empty() or not c.get("name",c.id) is String or not uint(c.get("start_frame")) or not uint(c.get("end_frame")) or not uint(c.get("play_count")) or c.start_frame > c.end_frame or c.end_frame >= frames.size() or clips.any(func(v): return v.id == c.id):
				warn("잘못된 클립 무시"); continue
			clips.append({"id":c.id,"name":c.get("name",c.id),"start":int(c.start_frame),"end":int(c.end_frame),"plays":int(c.play_count)})
		for g in obj.get("mask_groups",[]):
			if not g is Dictionary or not g.get("id") is String or g.id.is_empty() or not g.get("name",g.id) is String or not g.get("palette_indices") is Array or g.palette_indices.any(func(i): return not uint(i) or i >= mask_count) or groups.any(func(v): return v.id == g.id):
				warn("잘못된 마스크 그룹 무시"); continue
			var unique = {}
			for index in g.palette_indices: unique[int(index)] = true
			if unique.size() != g.palette_indices.size(): warn("중복 마스크 인덱스 무시"); continue
			groups.append({"id":g.id,"name":g.get("name",g.id),"indices":unique.keys()})
		if obj.has("sockets"): parse_sockets(obj.sockets)

func parse_sockets(obj: Variant):
	if not obj is Dictionary or not obj.get("definitions") is Array or not obj.get("frames") is Array:
		warn("소켓 정의 오류"); return
	var names: Array = []
	for d in obj.definitions:
		if not d is Dictionary or not d.get("name") is String or d.name.is_empty() or names.has(d.name): warn("소켓 이름 오류"); return
		names.append(d.name)
	if names.is_empty():
		if not obj.frames.is_empty(): warn("빈 소켓 정의에 프레임이 있습니다")
		return
	var records: Dictionary = {}
	for f in obj.frames:
		if not f is Dictionary or not uint(f.get("frame_index")) or f.frame_index >= frames.size() or not f.get("positions") is Array or f.positions.size() != names.size(): warn("소켓 프레임 오류"); continue
		var positions = []
		for p in f.positions:
			if not p is Array or p.size() < 2 or p.size() > 3 or p.any(func(n): return not finite(n)): break
			positions.append([p[0],p[1],p[2] if p.size() == 3 else 0])
		if positions.size() != names.size(): warn("소켓 좌표 오류"); continue
		if records.has(int(f.frame_index)): warn("중복 소켓 프레임 무시"); continue
		records[int(f.frame_index)] = positions
	if not records.has(0): warn("소켓 0번 프레임이 없습니다"); return
	var keys = records.keys(); keys.sort()
	sockets = {"names":names,"records":records,"keys":keys}

func sockets_at(frame: int) -> Array:
	if sockets.is_empty() or frame < 0: return []
	var keys = sockets.keys
	var low = 0; var high = keys.size()
	while low < high:
		var mid = (low + high) / 2
		if keys[mid] <= frame: low = mid + 1
		else: high = mid
	return sockets.records[keys[low-1]] if low > 0 else []
