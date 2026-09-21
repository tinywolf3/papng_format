extends RefCounted
const Doc = preload("res://core/document.gd")
const Player = preload("res://core/player.gd")
var thread = Thread.new()
var mutex = Mutex.new()
var commands: Array = []
var events: Array = []
var generation = 0
var stopping = false
var parent
var accessory
var playing = false
var settling = false
var clip = -1
var parent_info: Dictionary = {}
var child_info: Dictionary = {}
var token = 0
var last_status = 0

func start(): thread.start(run)
func close():
	mutex.lock(); stopping = true; mutex.unlock()
	if thread.is_started(): thread.wait_to_finish()
func send(command: Dictionary):
	mutex.lock()
	if command.type == "open": generation += 1
	command.generation = generation
	commands.append(command)
	mutex.unlock()
func poll() -> Array:
	mutex.lock(); var result = events; events = []; mutex.unlock()
	return result
func cancelled() -> bool:
	mutex.lock(); var result = stopping or generation != token; mutex.unlock()
	return result
func emit(event: Dictionary):
	event.generation = token
	mutex.lock()
	if token == generation:
		# A slow display should never accumulate a backlog of full image buffers.
		if event.type == "frame": events = events.filter(func(e): return e.type != "frame")
		events.append(event)
	mutex.unlock()

func describe(doc, path: String) -> Dictionary:
	var colors: Dictionary = {}
	for index in doc.frames.size():
		if cancelled(): return {}
		var mask = doc.mask(index)
		if mask.is_empty(): continue
		var pixels = doc.decode(index)
		if pixels.is_empty(): return {}
		for pos in range(0,mask.size(),2):
			if pos % 16384 == 0 and cancelled(): return {}
			var word = (mask[pos]<<8)|mask[pos+1]
			var at = pos*2
			if not word & 0x8000 or pixels[at+3] == 0: continue
			var id = word & 0x7fff
			if not colors.has(id): colors[id] = [0.0,0.0,0.0,0.0]
			var sum = colors[id]
			for c in 3: sum[c] += pixels[at+c]*pixels[at+3]
			sum[3] += pixels[at+3]
		if index % 16 == 0: emit({"type":"busy","text":"마스크 원본색 확인 %d / %d" % [index+1,doc.frames.size()]})
	for id in colors:
		var sum = colors[id]
		colors[id] = Color(sum[0]/sum[3]/255.0,sum[1]/sum[3]/255.0,sum[2]/sum[3]/255.0)
	return {"path":path,"width":doc.width,"height":doc.height,"frames":doc.frames.size(),"kind":doc.source_kind,"mask_count":doc.mask_count,"groups":doc.groups.duplicate(true),"colors":colors,"clips":doc.clips.duplicate(true),"sockets":doc.sockets.get("names",[]).duplicate(),"hints":doc.hints.duplicate(true),"metadata":doc.metadata_text.left(65536)}

func open_resource(path: String, child: bool):
	playing = false; settling = true
	emit({"type":"busy","text":"파일을 읽는 중…"})
	var doc = Doc.new()
	if not doc.load_file(path,cancelled):
		if not cancelled(): emit({"type":"error","text":doc.error})
		return
	var info = describe(doc,path)
	if cancelled(): return
	if not doc.error.is_empty(): emit({"type":"error","text":doc.error}); return
	var player = Player.new(doc)
	player.restart()
	if not doc.error.is_empty(): emit({"type":"error","text":doc.error}); return
	if child:
		accessory = player; child_info = info
	else:
		parent = player; parent_info = info; accessory = null; child_info = {}; clip = -1
		playing = true
	settling = (parent.visible < 0 and not parent.ended) or (accessory != null and accessory.visible < 0 and not accessory.ended)
	print("PAPNG_VIEWER_READY kind=",doc.source_kind," frames=",doc.frames.size()," child=",child)
	emit({"type":"info","parent":parent_info,"child":child_info,"new_child":child})
	publish()

func publish():
	if parent == null: return
	var result = {"type":"frame","pixels":parent.presented,"marks":parent.presented_marks,"frame":parent.visible,"visit":parent.visit.get("frame",-1),"playing":playing,"settling":settling,"ended":parent.ended,"start":parent.interval.start,"end":parent.interval.end,"num":parent.visit.get("num",0),"den":parent.visit.get("den",100),"poses":parent.doc.sockets_at(parent.visible),"warnings":parent.doc.warnings.duplicate(),"cache":parent.cache_bytes,"child_pixels":PackedByteArray(),"child_frame":-1}
	if accessory != null:
		result.child_pixels = accessory.presented; result.child_frame = accessory.visible
		for warning in accessory.doc.warnings: result.warnings.append("부속: " + warning)
	emit(result)
	last_status = Time.get_ticks_usec()
	parent.changed = false
	if accessory != null: accessory.changed = false

func run():
	var before = Time.get_ticks_usec()
	while true:
		mutex.lock(); var stop = stopping; var pending = commands; commands = []; mutex.unlock()
		if stop: break
		var now = Time.get_ticks_usec()
		var elapsed = (now-before)/1000000.0
		before = now
		for cmd in pending:
			token = cmd.generation
			if cancelled(): continue
			if cmd.type == "open":
				# Clear the old view even when a replacement fails.
				parent = null; accessory = null; parent_info = {}; child_info = {}
				open_resource(cmd.path,false)
			elif parent != null:
				match cmd.type:
					"attach": open_resource(cmd.path,true)
					"detach": accessory = null; child_info = {}; emit({"type":"info","parent":parent_info,"child":child_info})
					"play":
						if parent.ended:
							parent.restart(clip)
							if accessory != null: accessory.restart()
						playing = not playing; settling = false
					"pause": playing = false; settling = false
					"restart", "clip":
						playing = false; settling = true
						if cmd.type == "clip": clip = cmd.index
						parent.restart(clip)
						if accessory != null: accessory.restart()
					"seek", "step":
						playing = false; settling = true
						if cmd.type == "seek": parent.ended = false; parent.enter(clampi(cmd.frame,parent.interval.start,parent.interval.end))
						else: parent.advance()
						parent.tick(0)
						if accessory != null: accessory.restart()
					"hue", "select_mask":
						playing = false; settling = true
						var target = accessory if cmd.get("child",false) else parent
						if target != null:
							if cmd.type == "hue":
								if cmd.get("reset",false): target.offsets.clear()
								else: target.offsets[cmd.index] = cmd.offset
							else: target.selected_mask = cmd.index
							target.invalidate()
						parent.restart(clip)
						if accessory != null: accessory.restart()
				publish()
			elapsed = 0.0
			before = Time.get_ticks_usec()
		if parent != null and not cancelled():
			if settling and not playing:
				var was_settling = settling
				if parent.visible < 0 and not parent.ended: parent.tick(0)
				if accessory != null and accessory.visible < 0 and not accessory.ended: accessory.tick(0)
				settling = (parent.visible < 0 and not parent.ended) or (accessory != null and accessory.visible < 0 and not accessory.ended)
				if was_settling != settling: parent.changed = true
			if playing:
				parent.tick(elapsed)
				if accessory != null and not parent.ended: accessory.tick(elapsed)
				settling = (parent.visible < 0 and not parent.ended) or (accessory != null and accessory.visible < 0 and not accessory.ended)
				if parent.ended: playing = false; parent.changed = true
			if accessory != null and not accessory.doc.error.is_empty():
				parent.doc.warn("부속 로딩 중단: " + accessory.doc.error)
				accessory = null; child_info = {}; parent.changed = true
				emit({"type":"info","parent":parent_info,"child":child_info})
			if not parent.doc.error.is_empty():
				playing = false; emit({"type":"error","text":parent.doc.error}); parent = null
			elif parent.changed or (accessory != null and accessory.changed) or (Time.get_ticks_usec()-last_status > 500000): publish()
		OS.delay_usec(4000)
