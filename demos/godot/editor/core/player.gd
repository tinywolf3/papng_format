extends RefCounted
## Canonical APNG reconstruction, separate from playback visits and random draws.
var doc
var offsets: Dictionary = {}
var selected_mask = -1
var state: Dictionary = {}
var cache: Dictionary = {}
var cache_bytes = 0
var budget = 32 * 1024 * 1024
var source_cache: Dictionary = {}
var source_bytes = 0
var priority: Dictionary = {0:3}
var stamp = 0
var rng = RandomNumberGenerator.new()
var interval: Dictionary
var visit: Dictionary = {}
var ended = false
var completed = 0
var visible = -1
var presented = PackedByteArray()
var presented_marks = PackedByteArray()
var remaining = 0.0
var changed = false
var zero_visits = 0

func _init(document):
	doc = document
	rng.randomize()
	interval = {"start":0,"end":doc.frames.size()-1,"plays":doc.plays}
	for frame in doc.controls:
		for c in doc.controls[frame]:
			if valid_control(c,frame) and c.type in [2,3]:
				var target = frame + c.values[0] if c.type == 2 else c.values[0]
				priority[target] = 6
	for clip in doc.clips: priority[clip.start] = 5

func uniform(limit: int) -> int:
	var domain: int = 0x100000000
	var threshold = domain - domain % limit
	while true:
		var draw = rng.randi()
		if draw < threshold: return draw % limit
	return 0

func sample(distribution: Dictionary, minimum: int, maximum: int) -> int:
	if distribution.kind == 4:
		var total = 0
		for item in distribution.items: total += item.weight
		var draw = uniform(total)
		for item in distribution.items:
			if draw < item.weight: return item.value
			draw -= item.weight
	var n = maximum - minimum + 1
	if distribution.kind == 0: return minimum + uniform(n)
	# Exact integer rejection sampling avoids overflow of N*(N+1) at N=2^32.
	# Each (candidate,height) pair is equiprobable; accepted heights are its weight.
	var peak = (n+1)/2 if distribution.kind == 1 else n
	while true:
		var i = uniform(n)
		var weight = mini(i+1,n-i) if distribution.kind == 1 else n-i if distribution.kind == 2 else i+1
		if uniform(peak) < weight: return minimum + i
	return minimum

func target_ok(value: int) -> bool:
	return value >= interval.start and value <= interval.end

func valid_control(c: Dictionary, frame: int) -> bool:
	if not c.valid: return false
	var v = c.values
	if c.type == 0: return true
	if c.type == 2: return target_ok(frame+v[0])
	if c.type == 3: return target_ok(v[0])
	var index = v[3 if c.type == 1 else 2]
	if index >= doc.distributions.size() or not doc.distributions[index].valid: return false
	var d = doc.distributions[index]
	var valid_value = func(value): return value >= 0 if c.type == 1 else target_ok(value+frame if c.type == 4 else value)
	if d.kind == 4: return d.items.all(func(item): return item.weight == 0 or valid_value.call(item.value))
	return v[0] <= v[1] and valid_value.call(v[0]) and valid_value.call(v[1])

func resolve(frame: int) -> Dictionary:
	if not doc.controls.has(frame): return {}
	for c in doc.controls[frame]:
		if valid_control(c,frame): return c
	doc.warn("프레임 %d 제어 오류: 10 ms 후 순차 진행" % frame)
	return {"type":-1,"values":[]}

func enter(frame: int):
	if not seek_canvas(frame): return
	var c = resolve(frame)
	var f = doc.frames[frame]
	var num = f.num; var den = f.den
	if not c.is_empty():
		if c.type == -1: num = 1; den = 100
		elif c.type == 0: num = c.values[0]; den = c.values[1]
		elif c.type == 1:
			num = sample(doc.distributions[c.values[3]],c.values[0],c.values[1]); den = c.values[2]
	if den == 0: den = 100
	visit = {"frame":frame,"num":num,"den":den,"control":c}
	remaining = float(num)/den
	if num > 0:
		visible = frame; presented = state.pixels; presented_marks = state.marks
		changed = true; zero_visits = 0
	else: zero_visits += 1

func restart(clip: int = -1):
	interval = doc.clips[clip].duplicate() if clip >= 0 else {"start":0,"end":doc.frames.size()-1,"plays":doc.plays}
	state = {}; visit = {}; ended = false; completed = 0; visible = -1; zero_visits = 0
	presented = PackedByteArray(); presented_marks = PackedByteArray(); changed = true
	enter(interval.start)
	tick(0.0)

func advance():
	if ended or visit.is_empty(): return
	var c = visit.control
	var frame = visit.frame
	var target = frame + 1
	var sequential = true
	if not c.is_empty() and c.type >= 2:
		sequential = false
		match c.type:
			2: target = frame + c.values[0]
			3: target = c.values[0]
			4,5:
				var value = sample(doc.distributions[c.values[2]],c.values[0],c.values[1])
				target = value + frame if c.type == 4 else value
	if sequential and target > interval.end:
		completed += 1
		if interval.plays != 0 and completed >= interval.plays:
			ended = true; return
		state = {}; target = interval.start
	if not sequential: priority[target] = mini(12,priority.get(target,0)+1)
	enter(target)

func tick(seconds: float):
	if ended or visit.is_empty(): return
	remaining -= seconds
	var started = Time.get_ticks_usec()
	var count = 0
	while remaining <= 0 and not ended and doc.error.is_empty():
		var debt = remaining
		advance()
		remaining += debt
		count += 1
		if count >= 128 or Time.get_ticks_usec()-started > 8000:
			if zero_visits >= 128: doc.warn("시간이 진행되지 않는 숨김 프레임 순환: 일시정지할 수 있습니다")
			break

func invalidate():
	state = {}; cache.clear(); cache_bytes = 0

func raw(frame: int) -> PackedByteArray:
	if source_cache.has(frame):
		var bytes = source_cache[frame]; source_cache.erase(frame); source_cache[frame] = bytes
		return bytes
	var bytes = doc.decode(frame)
	if bytes.size() <= budget:
		while source_bytes + bytes.size() > budget:
			var key = source_cache.keys()[0]; source_bytes -= source_cache[key].size(); source_cache.erase(key)
		source_cache[frame] = bytes; source_bytes += bytes.size()
	return bytes

static func adjustment(value) -> Vector3:
	var scalar = 0.0 if value is Vector3 else float(value)
	var result = value if value is Vector3 else Vector3(fposmod(scalar,360.0) if is_finite(scalar) else 0,0,0)
	for i in 3:
		if not is_finite(result[i]): result[i]=0
	result.x=fposmod(result.x,360.0); result.y=clampf(result.y,-1,1); result.z=clampf(result.z,-1,1)
	return result

static func hue(r: int, g: int, b: int, degrees: float, ds: float = 0, dv: float = 0) -> PackedByteArray:
	var angle = fposmod(degrees,360.0) if is_finite(degrees) else 0.0
	ds = clampf(ds,-1,1) if is_finite(ds) else 0.0
	dv = clampf(dv,-1,1) if is_finite(dv) else 0.0
	if angle == 0 and ds == 0 and dv == 0: return PackedByteArray([r,g,b])
	var high = maxi(r,maxi(g,b)); var low = mini(r,mini(g,b)); var chroma = high-low
	var sector = 0.0 if chroma == 0 else float(g-b)/chroma if high == r else float(b-r)/chroma+2 if high == g else float(r-g)/chroma+4
	sector = fposmod(sector+angle/60.0,6.0)
	var sat=clampf((0.0 if high == 0 else float(chroma)/high)+ds,0,1)
	var val=clampf(high+dv*255.0,0,255)
	var c=val*sat; var m=val-c; var x=c*(1-absf(fposmod(sector,2.0)-1))
	var channels = [[c,x,0],[x,c,0],[0,c,x],[0,x,c],[x,0,c],[c,0,x]][int(floor(sector))]
	return PackedByteArray([clampi(int(floor(channels[0]+m+0.5+1e-10)),0,255),clampi(int(floor(channels[1]+m+0.5+1e-10)),0,255),clampi(int(floor(channels[2]+m+0.5+1e-10)),0,255)])

func dispose():
	var f = doc.frames[state.frame]
	if f.dispose == 2:
		state.pixels = state.previous; state.marks = state.previous_marks
	elif f.dispose == 1:
		for y in range(f.y,f.y+f.height):
			for x in range(f.x,f.x+f.width):
				var at = (y*doc.width+x)*4
				for c in 4: state.pixels[at+c] = 0; state.marks[at+c] = 0
	state.previous = PackedByteArray(); state.previous_marks = PackedByteArray()

func draw_frame(index: int):
	var f = doc.frames[index]
	var source = raw(index)
	if source.is_empty(): return
	var mask = doc.mask(index)
	if f.dispose == 2:
		state.previous = state.pixels.duplicate(); state.previous_marks = state.marks.duplicate()
	if mask.is_empty() and f.blend == 0 and f.width == doc.width and f.height == doc.height:
		state.pixels = source
		state.marks = PackedByteArray(); state.marks.resize(source.size())
		state.frame = index
		return
	for y in f.height:
		if y % 32 == 0 and doc.cancel.is_valid() and doc.cancel.call(): return
		for x in f.width:
			var s = (y*f.width+x)*4; var dest = ((y+f.y)*doc.width+x+f.x)*4
			var word = 0 if mask.is_empty() else (mask[s/2]<<8)|mask[s/2+1]
			var assigned = (word & 0x8000) != 0
			var setting = offsets.get(word & 0x7fff,0.0) if assigned else 0.0
			var finite = setting.is_finite() if setting is Vector3 else is_finite(float(setting))
			if not finite: doc.warn("유한하지 않은 HSV 변화량: 해당 성분을 0으로 복구")
			var delta = adjustment(setting)
			var rgb = hue(source[s],source[s+1],source[s+2],delta.x,delta.y,delta.z)
			var sa = source[s+3]/255.0; var da = state.pixels[dest+3]/255.0
			var a = sa+da*(1-sa)
			if f.blend == 0 or source[s+3] == 255:
				for c in 3: state.pixels[dest+c] = rgb[c]
				state.pixels[dest+3] = source[s+3]
			elif sa > 0:
				for c in 3: state.pixels[dest+c] = int(floor((rgb[c]*sa+state.pixels[dest+c]*da*(1-sa))/a+0.5))
				state.pixels[dest+3] = int(floor(a*255+0.5))
			var selected = assigned and (selected_mask < 0 or (word & 0x7fff) == selected_mask)
			var coverage = sa if selected else 0.0
			if f.blend == 1: coverage += state.marks[dest+3]/255.0*(1-sa)
			state.marks[dest] = 255; state.marks[dest+1] = 80; state.marks[dest+2] = 210
			state.marks[dest+3] = int(floor(coverage*255+0.5))
	state.frame = index

func state_size(s: Dictionary) -> int:
	return s.pixels.size()+s.marks.size()+s.previous.size()+s.previous_marks.size()

func remember():
	var frame = state.frame
	var bytes = state_size(state)
	if bytes > budget: return
	if cache.has(frame): cache_bytes -= cache[frame].bytes; cache.erase(frame)
	stamp += 1
	cache[frame] = {"state":state.duplicate(true),"bytes":bytes,"used":stamp}
	cache_bytes += bytes
	while cache_bytes > budget:
		var victim = -1; var score = INF
		for key in cache:
			var value = cache[key].used + priority.get(key,0)*8
			if value < score: score = value; victim = key
		cache_bytes -= cache[victim].bytes; cache.erase(victim)

func seek_canvas(target: int) -> bool:
	if not state.is_empty() and state.frame == target: return true
	if cache.has(target):
		stamp += 1; cache[target].used = stamp; state = cache[target].state.duplicate(true); return true
	var best = state.get("frame",-1)
	if best > target: best = -1; state = {}
	for key in cache:
		if key < target and key > best: best = key; state = cache[key].state.duplicate(true)
	if best < 0:
		var blank = PackedByteArray(); blank.resize(doc.width*doc.height*4)
		state = {"frame":-1,"pixels":blank.duplicate(),"marks":blank.duplicate(),"previous":PackedByteArray(),"previous_marks":PackedByteArray()}
	for i in range(state.frame+1,target+1):
		if doc.cancel.is_valid() and doc.cancel.call(): return false
		if state.frame >= 0: dispose()
		draw_frame(i)
		if doc.cancel.is_valid() and doc.cancel.call(): return false
		if not doc.error.is_empty(): return false
		if i == target or priority.has(i) or i % 16 == 0: remember()
	return true
