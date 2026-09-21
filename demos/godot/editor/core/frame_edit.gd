extends RefCounted
## Structural edits preserve destinations and socket poses or fail without mutation.
const Metadata = preload("res://core/metadata_edit.gd")

static func remap(model, order: Array, added: Dictionary = {}) -> String:
	var mapping = {}; var frames = []; var distributions = model.distributions.duplicate(true)
	for index in order.size():
		var old = int(order[index])
		if old >= 0: mapping[old] = index; frames.append(model.frames[old].duplicate(true))
		else: frames.append(added[index].duplicate(true))
	for index in frames.size():
		var c = frames[index].control
		if c.is_empty() or c.type<2: continue
		var old = int(order[index]); var v = c.values
		if c.type in [2,3]:
			var target = old+int(v[0]) if c.type==2 else int(v[0])
			if not mapping.has(target): return "프레임 %d가 삭제 대상 %d를 참조합니다. 먼저 이동 제어를 수정하세요." % [old,target]
			v[0] = mapping[target]-index if c.type==2 else mapping[target]
			continue
		var d = distributions[int(v[2])]
		var relative = c.type==4
		var values = []; var weights = []
		if d.kind==4:
			for item in d.items:
				if item.weight==0: continue
				values.append(int(item.value)); weights.append(int(item.weight))
		else:
			var lo = int(v[0]); var hi = int(v[1]); var n = hi-lo+1
			if n>model.frames.size(): return "랜덤 이동 범위를 먼저 확인하세요."
			for i in n:
				values.append(lo+i); weights.append(1 if d.kind==0 else mini(i+1,n-i) if d.kind==1 else n-i if d.kind==2 else i+1)
		var changed = false; var shift = 0; var translated = true
		for j in values.size():
			var target = values[j]+old if relative else values[j]
			if not mapping.has(target): return "랜덤 이동이 삭제 대상을 참조합니다. 먼저 해당 제어를 수정하세요."
			var result = mapping[target]-index if relative else mapping[target]
			if j==0: shift = result-values[j]
			elif result-values[j] != shift: translated = false
			changed = changed or result != values[j]
			values[j] = result
		if not changed: continue
		if d.kind!=4 and translated: v[0]+=shift; v[1]+=shift; continue
		var common = weights[0]
		for weight in weights:
			var b = weight
			while b: var rest = common%b; common=b; b=rest
		var items = []
		for j in values.size():
			if values[j]<-8388608 or values[j]>8388607 or weights[j]/common>255: return "이 재배열은 현재 가중치 형식으로 정확히 표현할 수 없습니다. 랜덤 이동을 먼저 수정하세요."
			items.append({"value":values[j],"weight":weights[j]/common})
		var id = -1
		for j in distributions.size():
			if distributions[j].kind==4 and distributions[j].items==items: id=j; break
		if id<0:
			if distributions.size()==256: return "분포 팔레트가 가득 차 재배열 대상 분포를 추가할 수 없습니다."
			id=distributions.size(); distributions.append({"kind":4,"valid":true,"items":items})
		v[2]=id
	var metadata = model.metadata(); var text = model.metadata_text
	if metadata.has("clips"):
		var clips = []
		for old_clip in metadata.clips:
			var clip = old_clip.duplicate(true); var indices=[]
			for old in mapping:
				if old>=clip.start_frame and old<=clip.end_frame: indices.append(mapping[old])
			if indices.is_empty(): continue
			indices.sort()
			# A clip is an interval; reject noncontiguous moves instead of adding unrelated frames.
			if indices[-1]-indices[0]+1 != indices.size(): return "클립 '%s'의 프레임이 분리되는 재배열입니다. 클립 범위를 먼저 수정하세요." % clip.id
			clip.start_frame=indices[0]; clip.end_frame=indices[-1]; clips.append(clip)
		text=Metadata.set_member(text,"clips",clips)
	var doc=model.runtime()
	if not doc.sockets.is_empty():
		var sockets=metadata.sockets.duplicate(true); var records=[]; var last=[]
		for i in order.size():
			var old=int(order[i]); var pose=doc.sockets_at(old) if old>=0 else last
			if pose.is_empty(): pose=doc.sockets_at(0)
			if i==0 or pose!=last: records.append({"frame_index":i,"positions":pose.duplicate(true)})
			last=pose.duplicate(true)
		sockets.frames=records; text=Metadata.set_member(text,"sockets",sockets)
	model.frames=frames; model.distributions=distributions; model.metadata_text=text
	model.selected=clampi(mapping.get(model.selected,model.selected),0,frames.size()-1); model.touch()
	return ""
