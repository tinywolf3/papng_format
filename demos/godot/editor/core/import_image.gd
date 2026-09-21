extends RefCounted
## Native decoders first. Optional ImageMagick broadens runtime import formats.
var error = ""
var decoder = ""
var cancelled = false
var converter = ""
const NATIVE = ["png","jpg","jpeg","webp","bmp","tga","svg","exr","hdr","dds","ktx"]
const EXTRA = ["gif","tif","tiff","avif","heic","heif","jxl","ico","psd","psb","xcf","ora","jp2","j2k","pcx","ppm","pgm","pbm","pnm","qoi","dng","cr2","cr3","nef","arw","raf","rw2"]
func find_converter() -> String:
	if not converter.is_empty() and FileAccess.file_exists(converter): return converter
	var executable = "magick.exe" if OS.get_name()=="Windows" else "magick"
	for folder in OS.get_environment("PATH").split(";" if OS.get_name()=="Windows" else ":"):
		var candidate=folder.path_join(executable)
		if FileAccess.file_exists(candidate): return candidate
	return ""
func load_image(path: String) -> Image:
	error=""; decoder=""; cancelled=false
	var extension=path.get_extension().to_lower()
	if extension in NATIVE:
		var native=Image.new()
		if native.load(path)==OK and not native.is_empty():
			if native.is_compressed() and native.decompress()!=OK: error="압축 텍스처를 해제하지 못했습니다"; return null
			if native.get_width()*native.get_height()>32*1024*1024: error="가져오기 이미지가 32 메가픽셀 처리 예산을 초과합니다"; return null
			native.clear_mipmaps(); native.convert(Image.FORMAT_RGBA8); decoder="Godot"; return native
	if not extension in NATIVE+EXTRA: error="지원하는 이미지 확장자가 아닙니다"; return null
	var program=find_converter()
	if program.is_empty(): error="이 형식은 ImageMagick 7이 필요합니다. 설치 후 설정에서 magick 실행 파일을 지정하세요."; return null
	var folder=ProjectSettings.globalize_path("user://import-cache")
	DirAccess.make_dir_recursive_absolute(folder)
	var output=folder.path_join("import-"+str(Time.get_ticks_usec())+".png")
	# Arrays go directly to the process API, never through a command shell.
	# Pixel selectors permit the first page/layer of GIF/TIFF/PSD and similar files.
	var args=PackedStringArray(["-limit","memory","256MiB","-limit","map","512MiB","-limit","disk","512MiB","-limit","time","45","-define","registry:temporary-path="+folder,path+"[0]","-auto-orient","-resize","4096x4096>","-depth","8","PNG32:"+output])
	var pid=OS.create_process(program,args,false)
	if pid<0: error="ImageMagick을 실행하지 못했습니다"; return null
	var deadline=Time.get_ticks_msec()+60000
	while OS.is_process_running(pid):
		if cancelled or Time.get_ticks_msec()>deadline:
			OS.kill(pid); error="가져오기를 취소했습니다" if cancelled else "이미지 변환이 60초를 초과했습니다"; break
		OS.delay_msec(25)
	var image=Image.new()
	if error.is_empty() and (not FileAccess.file_exists(output) or image.load(output)!=OK): error="이미지 변환에 실패했습니다. 설치된 ImageMagick의 해당 형식 지원을 확인하세요."
	if FileAccess.file_exists(output): DirAccess.remove_absolute(output)
	if not error.is_empty(): return null
	image.convert(Image.FORMAT_RGBA8); decoder="ImageMagick · 첫 이미지 / 최대 4096×4096"; return image

static func pixelize(source: Image, rect: Rect2i, size: Vector2i, sampling: int, levels: int) -> Image:
	rect=rect.intersection(Rect2i(Vector2i.ZERO,source.get_size()))
	if not rect.has_area() or size.x<1 or size.y<1 or size.x*size.y>4194304: return null
	var result=source.get_region(rect)
	result.resize(size.x,size.y,sampling)
	result.convert(Image.FORMAT_RGBA8)
	if levels>1:
		var bytes=result.get_data()
		for at in range(0,bytes.size(),4):
			for c in 3: bytes[at+c]=roundi(roundf(bytes[at+c]*(levels-1)/255.0)*255/(levels-1))
		result=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,bytes)
	return result
