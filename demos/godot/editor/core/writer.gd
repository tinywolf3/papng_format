extends RefCounted
const Bin = preload("res://core/binary.gd")
const SIGNATURE = [137,80,78,71,13,10,26,10]

static func packed(values: Array, sizes: Array) -> PackedByteArray:
	var out = PackedByteArray()
	for i in values.size(): out.append_array(Bin.be(int(values[i]),sizes[i]))
	return out

static func pixels(frame: Dictionary) -> PackedByteArray:
	var raw = PackedByteArray()
	var stride = frame.width*4
	for y in frame.height:
		raw.append(0); raw.append_array(frame.rgba.slice(y*stride,(y+1)*stride))
	return raw.compress(FileAccess.COMPRESSION_DEFLATE)

static func extension(model) -> PackedByteArray:
	var h = model.hints
	var flags = int(h.has("display")) | (int(h.has("bbox"))<<1) | (int(h.has("scale"))<<2) | (int(h.has("pivot"))<<3)
	var out = PackedByteArray([80,65,80,78,71,0,0,0])+packed([1,1,56,flags],[2,2,4,4])
	var fields = h.get("display",[0,0])+h.get("bbox",[0,0,0,0])+[h.get("scale",0)]+h.get("pivot",[0,0])
	for value in fields: out.append_array(Bin.be(int(value),4))
	out.append_array(Bin.be(model.mask_count,2)); out.append(model.distributions.size()-1)
	for d in model.distributions.slice(1):
		var payload = PackedByteArray()
		if d.kind == 4:
			payload.append_array(Bin.be(d.items.size(),4))
			for item in d.items: payload.append_array(packed([item.value,item.weight],[3,1]))
		out.append(d.kind); out.append_array(Bin.be(payload.size(),3)); out.append_array(payload)
	var controls = []
	for i in model.frames.size():
		if not model.frames[i].control.is_empty(): controls.append([i,model.frames[i].control])
	out.append_array(Bin.be(controls.size(),4))
	for entry in controls:
		var control = entry[1]
		var sizes = [[2,2],[2,2,2,1],[4],[4],[4,4,1],[4,4,1]][control.type]
		var payload = packed(control.values,sizes)
		out.append_array(packed([entry[0],control.type,payload.size()],[4,4,4])); out.append_array(payload)
	return out

static func masks(model) -> PackedByteArray:
	var maps = []; var references = []; var ids = {}
	for i in model.frames.size():
		var f = model.frames[i]
		if f.mask.is_empty(): continue
		var active = false
		for n in range(0,f.mask.size(),2):
			if f.mask[n] & 0x80: active = true; break
		if not active: continue
		var hash = HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(f.mask)
		var key = "%dx%d:%s" % [f.width,f.height,hash.finish().hex_encode()]
		if not ids.has(key):
			ids[key] = maps.size(); maps.append({"w":f.width,"h":f.height,"data":f.mask.compress(FileAccess.COMPRESSION_DEFLATE)})
		references.append([i,ids[key]])
	if references.is_empty(): return PackedByteArray()
	var out = Bin.be(maps.size(),4)
	for m in maps: out.append_array(packed([m.w,m.h,m.data.size()],[4,4,4])); out.append_array(m.data)
	out.append_array(Bin.be(references.size(),4))
	for binding in references: out.append_array(packed(binding,[4,4]))
	return out

static func encode(model) -> PackedByteArray:
	var out = PackedByteArray(SIGNATURE)
	out.append_array(Bin.chunk("IHDR",packed([model.width,model.height,8,6,0,0,0],[4,4,1,1,1,1,1])))
	out.append_array(Bin.chunk("acTL",packed([model.frames.size(),model.plays],[4,4])))
	out.append_array(Bin.chunk("paEX",extension(model)))
	var planes = masks(model)
	if not planes.is_empty(): out.append_array(Bin.chunk("paMD",planes))
	if not model.metadata_text.is_empty():
		out.append_array(Bin.chunk("iTXt","PAPNG.Metadata".to_utf8_buffer()+PackedByteArray([0,0,0,0,0])+model.metadata_text.to_utf8_buffer()))
	for chunk in model.ancillary: out.append_array(Bin.chunk(chunk.name,chunk.data))
	var sequence = 0
	# A separate fallback image permits the first animation frame to be a subrectangle.
	var poster = model.frames[0].width != model.width or model.frames[0].height != model.height or model.frames[0].x != 0 or model.frames[0].y != 0
	if poster:
		var rgba = model.composite(0)
		out.append_array(Bin.chunk("IDAT",pixels({"width":model.width,"height":model.height,"rgba":rgba})))
	for i in model.frames.size():
		var f = model.frames[i]
		out.append_array(Bin.chunk("fcTL",packed([sequence,f.width,f.height,f.x,f.y,f.num,f.den,f.dispose,f.blend],[4,4,4,4,4,2,2,1,1])))
		sequence += 1
		var data = pixels(f)
		if i == 0 and not poster: out.append_array(Bin.chunk("IDAT",data))
		else:
			out.append_array(Bin.chunk("fdAT",Bin.be(sequence,4)+data)); sequence += 1
	out.append_array(Bin.chunk("IEND",PackedByteArray()))
	return out
