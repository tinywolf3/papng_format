extends TabContainer
const UI = preload("res://ui/widgets.gd")
var host
var fields: Dictionary = {}
var mask_id: SpinBox
var mask_name: LineEdit
var hue: HSlider
var mask_label: Label
var socket_id: OptionButton
var socket_name: LineEdit
var sx: SpinBox
var sy: SpinBox
var sr: SpinBox
var clip_id: OptionButton
var clip_name: LineEdit
var clip_key: LineEdit
var clip_start: SpinBox
var clip_end: SpinBox
var clip_plays: SpinBox
var updating=false
var mask_swatches: HBoxContainer
var original_color: ColorRect
var shifted_color: ColorRect
func _ready(): build_frames(); build_masks(); build_sockets(); build_hints(); build_clips()
func model(): return host.model
func build_frames():
	var box=UI.tab(self,"프레임")
	fields.num=UI.spin(box,"지연 분자",0,65535); fields.den=UI.spin(box,"분모 (0 = 100)",0,65535)
	UI.label(box,"0 지연: 합성만 하고 출력하지 않음").add_theme_font_size_override("font_size",12)
	fields.blend=UI.options(box,"합성",["SOURCE · 교체","OVER · 알파 합성"])
	fields.dispose=UI.options(box,"처리 후",["NONE · 유지","BACKGROUND · 영역 지움","PREVIOUS · 이전 상태"])
	for key in ["x","y","width","height"]: fields[key]=UI.spin(box,{"x":"원본 영역 X","y":"Y","width":"너비","height":"높이"}[key],0 if key in ["x","y"] else 1,65535)
	UI.button(box,"프레임 속성 적용",apply_frame)
	box.add_child(HSeparator.new())
	fields.control=UI.options(box,"확장 제어",["없음 · APNG 지연","고정 지연","랜덤 지연","상대 이동","절대 이동","랜덤 상대 이동","랜덤 절대 이동"])
	fields.a=UI.spin(box,"값 A",-2147483648,4294967295); fields.b=UI.spin(box,"값 B",-2147483648,4294967295); fields.c=UI.spin(box,"분모",0,65535); fields.distribution=UI.spin(box,"분포 번호",0,255)
	fields.control_note=UI.label(box,""); fields.control_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; fields.control_note.add_theme_font_size_override("font_size",12)
	fields.control.item_selected.connect(func(_i): if not updating: control_defaults(); control_labels())
	UI.button(box,"확장 제어 적용",apply_control)
	UI.button(box,"공유 랜덤 분포 편집…",func(): host.show_distributions())
	fields.plays=UI.spin(box,"전체 반복 (0 = 무한)",0,4294967295)
	UI.button(box,"반복 적용",func(): host.edit("반복 횟수",func(): model().plays=int(fields.plays.value); model().touch()))
func build_masks():
	var box=UI.tab(self,"마스크")
	mask_label=UI.label(box,"")
	mask_id=UI.spin(box,"마스크 번호",0,32767); mask_id.value_changed.connect(func(_v): if not updating: host.canvas.mask_index=int(mask_id.value); sync_mask(); host.canvas.refresh())
	mask_name=UI.entry(box,"이름")
	var row=UI.row(box); UI.button(row,"추가",add_mask); UI.button(row,"이름 적용",rename_mask)
	UI.button(box,"선택 영역에 지정",func(): assign_mask(false))
	UI.button(box,"선택 영역의 마스크 해제",func(): assign_mask(true))
	UI.label(box,"M: 마스크 브러시 · Shift: 해제").add_theme_font_size_override("font_size",12)
	box.add_child(HSeparator.new())
	UI.label(box,"색상각 미리보기 (원본색은 보존)")
	UI.label(box,"색상칩: 현재 원본 프레임의 평균색").add_theme_font_size_override("font_size",12)
	hue=HSlider.new(); hue.min_value=-180; hue.max_value=180; hue.step=1; box.add_child(hue)
	hue.value_changed.connect(func(value): if not updating: host.set_hue(int(mask_id.value),value))
	mask_swatches=UI.row(box)
	for name in ["원본","변경"]:
		var group=VBoxContainer.new(); mask_swatches.add_child(group); UI.label(group,name)
		var swatch=ColorRect.new(); swatch.custom_minimum_size=Vector2(95,36); group.add_child(swatch)
		if name=="원본": original_color=swatch
		else: shifted_color=swatch
	UI.button(box,"미리보기 색상 초기화",func(): host.hues.clear(); host.preview_dirty=true; hue.set_value_no_signal(0); host.canvas.hue_offsets=host.hues; host.canvas.refresh())
	UI.button(box,"마스크 그룹 편집…",func(): host.show_groups())
func build_sockets():
	var box=UI.tab(self,"소켓")
	socket_id=UI.options(box,"연결 지점",[]); socket_id.item_selected.connect(func(_i): if not updating: sync_socket(); host.canvas.selected_socket=socket_id.selected; host.canvas.queue_redraw())
	socket_name=UI.entry(box,"이름")
	sx=UI.spin(box,"X",-2147483648,2147483647,0.5); sy=UI.spin(box,"Y",-2147483648,2147483647,0.5); sr=UI.spin(box,"회전 (도)",-36000,36000,0.1)
	UI.button(box,"현재 프레임에 적용",apply_socket)
	var row=UI.row(box); UI.button(row,"추가",add_socket); UI.button(row,"삭제",remove_socket)
	UI.label(box,"K: 캔버스에서 클릭해 위치 지정\n생략된 프레임은 이전 위치를 사용합니다.").add_theme_font_size_override("font_size",12)
	UI.button(box,"이 프레임의 위치 기록 제거",remove_pose)
	box.add_child(HSeparator.new())
	UI.button(box,"부속 PAPNG 미리보기…",func(): host.choose_accessory())
	UI.button(box,"부속 연결 해제",func(): host.clear_accessory())
func build_hints():
	var box=UI.tab(self,"힌트")
	for entry in [["display","출력 크기",["너비","높이"]],["bbox","바운딩 박스",["X","Y","너비","높이"]],["scale","픽셀 배수",["배수"]],["pivot","피벗",["X","Y"]]]:
		var name=entry[0]; fields[name+"_on"]=UI.check(box,entry[1]); fields[name+"_values"]=[]
		for label in entry[2]: fields[name+"_values"].append(UI.spin(box,label,-2147483648 if name=="pivot" else 0,2147483647))
	UI.button(box,"힌트 적용",func(): host.edit("헤더 힌트",func():
		var h={}
		for key in ["display","bbox","scale","pivot"]:
			if fields[key+"_on"].button_pressed:
				var values=[]
				for spin in fields[key+"_values"]: values.append(int(spin.value))
				h[key]=values[0] if key=="scale" else values
		model().hints=h; model().touch()))
func build_clips():
	var box=UI.tab(self,"클립")
	clip_id=UI.options(box,"애니메이션 구간",[]); clip_id.item_selected.connect(func(_i): if not updating: sync_clip())
	clip_key=UI.entry(box,"ID"); clip_name=UI.entry(box,"이름")
	clip_start=UI.spin(box,"시작 프레임",0,4294967295); clip_end=UI.spin(box,"끝 프레임",0,4294967295); clip_plays=UI.spin(box,"반복 (0 = 무한)",0,4294967295)
	UI.button(box,"클립 적용",func(): host.edit("클립 수정",func():
		var clips=model().metadata().get("clips",[])
		if clip_id.selected<0 or clip_id.selected>=clips.size(): return
		var c=clips[clip_id.selected]; c.id=clip_key.text; c.name=clip_name.text; c.start_frame=int(clip_start.value); c.end_frame=int(clip_end.value); c.play_count=int(clip_plays.value)
		model().put_metadata("clips",clips)))
	var row=UI.row(box)
	UI.button(row,"추가",func(): host.edit("클립 추가",func():
		var clips=model().metadata().get("clips",[]); var key="clip_"+str(Time.get_ticks_usec())
		clips.append({"id":key,"name":"새 클립","start_frame":model().selected,"end_frame":model().frames.size()-1,"play_count":0}); model().put_metadata("clips",clips)))
	UI.button(row,"삭제",func(): host.edit("클립 삭제",func():
		var clips=model().metadata().get("clips",[])
		if clip_id.selected>=0 and clip_id.selected<clips.size(): clips.remove_at(clip_id.selected); model().put_metadata("clips",clips)))
	UI.button(box,"선택 클립 미리보기",func(): host.start_playback(clip_id.selected))
	UI.button(box,"JSON5 전체 편집…",func(): host.show_metadata())
func sync():
	updating=true
	var m=model(); var f=m.frames[m.selected]
	for key in ["num","den","x","y","width","height"]: fields[key].value=f[key]
	fields.blend.select(f.blend); fields.dispose.select(f.dispose); fields.plays.value=m.plays
	fields.control.select(0 if f.control.is_empty() else f.control.type+1)
	control_defaults()
	if not f.control.is_empty():
		var v=f.control.values; fields.a.value=v[0]
		if v.size()>1: fields.b.value=v[1]
		if f.control.type==1: fields.c.value=v[2]; fields.distribution.value=v[3]
		elif f.control.type in [4,5]: fields.distribution.value=v[2]
	control_labels()
	mask_label.text="%d / 32,768 마스크" % m.mask_count; mask_id.max_value=maxi(0,m.mask_count-1); mask_id.value=mini(mask_id.value,mask_id.max_value)
	host.canvas.mask_index=int(mask_id.value); sync_mask()
	var chosen=socket_id.selected; socket_id.clear()
	for d in m.metadata().get("sockets",{}).get("definitions",[]): socket_id.add_item(d.name)
	if socket_id.item_count: socket_id.select(clampi(chosen,0,socket_id.item_count-1))
	sync_socket()
	for key in ["display","bbox","scale","pivot"]:
		fields[key+"_on"].button_pressed=m.hints.has(key)
		var values=[m.hints.get(key,1)] if key=="scale" else m.hints.get(key,[m.width,m.height] if key=="display" else [0,0,m.width,m.height] if key=="bbox" else [0,0])
		for i in values.size(): fields[key+"_values"][i].value=values[i]
	chosen=clip_id.selected; clip_id.clear()
	for c in m.metadata().get("clips",[]): clip_id.add_item(c.get("name",c.id))
	if clip_id.item_count: clip_id.select(clampi(chosen,0,clip_id.item_count-1))
	sync_clip(); updating=false
func control_defaults():
	fields.a.value=0; fields.b.value=0; fields.c.value=1000; fields.distribution.value=0
	match fields.control.selected:
		1: fields.a.value=1; fields.b.value=10
		2: fields.a.value=100; fields.b.value=500
		3: fields.a.value=0
		4: fields.a.value=model().selected
		5: fields.a.value=-model().selected; fields.b.value=model().frames.size()-1-model().selected
		6: fields.a.value=0; fields.b.value=model().frames.size()-1
func control_labels():
	var t=fields.control.selected
	fields.a.get_parent().visible=t>0; fields.b.get_parent().visible=t in [1,2,5,6]; fields.c.get_parent().visible=t==2; fields.distribution.get_parent().visible=t in [2,5,6]
	fields.a.get_parent().get_child(0).text=["","지연 분자","최소 분자","상대 이동량","대상 프레임","최소 이동량","최소 대상"][t]
	fields.b.get_parent().get_child(0).text="지연 분모" if t==1 else "최대 분자" if t==2 else "최대 이동량" if t==5 else "최대 대상"
	fields.control_note.text="이동 제어는 현재 프레임의 APNG 지연 후 실행됩니다.\n가중치 값 분포를 쓰면 범위 대신 분포의 값을 선택합니다." if t>=3 else "분포 0은 항상 균등분포입니다."
func apply_frame():
	host.edit("프레임 속성",func():
		var f=model().frames[model().selected]; var w=int(fields.width.value); var h=int(fields.height.value)
		if w*h*6>model().MAX_BYTES: host.action_error="프레임이 작업 예산을 초과합니다"; return
		if f.width!=w or f.height!=h:
			var resized=model().blank(w,h); var mask=PackedByteArray(); mask.resize(w*h*2)
			for y in mini(h,f.height):
				for x in mini(w,f.width):
					var old=(y*f.width+x)*4; var at=(y*w+x)*4
					for c in 4: resized.rgba[at+c]=f.rgba[old+c]
					if not f.mask.is_empty(): mask[at/2]=f.mask[old/2]; mask[at/2+1]=f.mask[old/2+1]
			f.rgba=resized.rgba; f.mask=mask
		for key in ["num","den","x","y","width","height"]: f[key]=int(fields[key].value)
		f.blend=fields.blend.selected; f.dispose=fields.dispose.selected; model().touch())
func apply_control():
	host.edit("프레임 제어",func():
		var type=fields.control.selected-1; var values=[]
		if type==0: values=[int(fields.a.value),int(fields.b.value)]
		elif type==1: values=[int(fields.a.value),int(fields.b.value),int(fields.c.value),int(fields.distribution.value)]
		elif type in [2,3]: values=[int(fields.a.value)]
		elif type in [4,5]: values=[int(fields.a.value),int(fields.b.value),int(fields.distribution.value)]
		model().frames[model().selected].control={} if type<0 else {"type":type,"values":values,"valid":true}; model().touch())
func sync_mask():
	var id=int(mask_id.value); var name="마스크 "+str(id)
	for group in model().metadata().get("mask_groups",[]):
		if group.palette_indices==[float(id)] or group.palette_indices==[id]: name=group.get("name",group.id); break
	mask_name.text=name; hue.set_value_no_signal(host.hues.get(id,0))
	var source=host.mask_reference(id); original_color.color=source; shifted_color.color=Color.from_hsv(fposmod(source.h+hue.value/360.0,1),source.s,source.v)
func add_mask():
	if model().mask_count>=32768: host.notify("마스크 한도에 도달했습니다."); return
	host.edit("마스크 추가",func(): model().mask_count+=1; model().touch())
	mask_id.value=model().mask_count-1; sync_mask()
func rename_mask():
	host.edit("마스크 이름",func():
		var id=int(mask_id.value)
		if id>=model().mask_count: return
		var groups=model().metadata().get("mask_groups",[]); var found=false
		for group in groups:
			if group.palette_indices==[float(id)] or group.palette_indices==[id]: group.name=mask_name.text; found=true; break
		if not found: groups.append({"id":"mask_"+str(id)+"_"+str(Time.get_ticks_usec()),"name":mask_name.text,"palette_indices":[id]})
		model().put_metadata("mask_groups",groups))
func assign_mask(clear: bool):
	if not clear and model().mask_count==0: host.notify("마스크를 먼저 추가하세요."); return
	host.edit("마스크 영역 지정",func():
		var rect=host.canvas.selection.intersection(model().frame_rect()) if host.canvas.selection.has_area() else model().frame_rect()
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x): model().set_pixel(Vector2i(x,y),PackedByteArray(),-1 if clear else int(mask_id.value))
		model().changed.emit())
func sync_socket():
	var doc=model().runtime(); var positions=doc.sockets_at(model().selected); var id=socket_id.selected
	if id<0 or id>=positions.size(): socket_name.text=""; sx.value=0; sy.value=0; sr.value=0; return
	socket_name.text=doc.sockets.names[id]; sx.value=positions[id][0]; sy.value=positions[id][1]; sr.value=positions[id][2]
	host.canvas.selected_socket=id
func apply_socket():
	host.edit("소켓 위치",func():
		var id=socket_id.selected; var sockets=model().metadata().get("sockets",{})
		if sockets.is_empty() or id<0: return
		sockets.definitions[id].name=socket_name.text
		var pose=model().runtime().sockets_at(model().selected).duplicate(true); pose[id]=[sx.value,sy.value,sr.value]
		var found=false
		for record in sockets.frames:
			if record.frame_index==model().selected: record.positions=pose; found=true; break
		if not found: sockets.frames.append({"frame_index":model().selected,"positions":pose})
		model().put_metadata("sockets",sockets))
func add_socket():
	host.edit("소켓 추가",func():
		var sockets=model().metadata().get("sockets",{"definitions":[],"frames":[{"frame_index":0,"positions":[]}]})
		if sockets.frames.is_empty(): sockets.frames.append({"frame_index":0,"positions":[]})
		sockets.definitions.append({"name":"socket_"+str(Time.get_ticks_usec())})
		for record in sockets.frames: record.positions.append([0,0,0])
		model().put_metadata("sockets",sockets))
func remove_socket():
	host.edit("소켓 삭제",func():
		var sockets=model().metadata().get("sockets",{}); var id=socket_id.selected
		if sockets.is_empty() or id<0: return
		sockets.definitions.remove_at(id)
		for record in sockets.frames: record.positions.remove_at(id)
		if sockets.definitions.is_empty(): sockets.frames=[]
		model().put_metadata("sockets",sockets))
func remove_pose():
	if model().selected==0: host.notify("0번 프레임의 기본 소켓 위치는 필요합니다."); return
	host.edit("소켓 위치 상속",func():
		var sockets=model().metadata().get("sockets",{})
		if sockets.is_empty(): return
		sockets.frames=sockets.frames.filter(func(f): return f.frame_index!=model().selected)
		model().put_metadata("sockets",sockets))
func sync_clip():
	var clips=model().metadata().get("clips",[])
	if clip_id.selected<0 or clip_id.selected>=clips.size(): clip_key.text=""; clip_name.text=""; return
	var clip=clips[clip_id.selected]; clip_key.text=clip.id; clip_name.text=clip.get("name",clip.id); clip_start.value=clip.start_frame; clip_end.value=clip.end_frame; clip_plays.value=clip.play_count
