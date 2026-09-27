extends RefCounted
## Only bundled or operating-system decoders are used at runtime.
const IO = preload("res://core/file_io.gd")
const NATIVE = ["png","jpg","jpeg","webp","bmp","tga","svg","exr","hdr","dds","ktx"]
const MAX_PIXELS = 32*1024*1024
var error = ""
var decoder = ""
var cancelled = false

func supported_extensions() -> Array: return NATIVE+["gif"]
func image_name(path: String) -> String: return path.get_file()

func normalize(image: Image) -> Image:
	if cancelled: error="가져오기를 취소했습니다"; return null
	if image.is_empty(): error="이미지가 비어 있습니다"; return null
	if image.get_width()*image.get_height()>MAX_PIXELS: error="이미지가 32 메가픽셀 처리 예산을 초과합니다"; return null
	if image.is_compressed() and image.decompress()!=OK: error="압축 텍스처를 해제하지 못했습니다"; return null
	image.clear_mipmaps(); image.convert(Image.FORMAT_RGBA8)
	return image

func load_image(path: String) -> Image:
	error=""; decoder=""
	var extension=image_name(path).get_extension().to_lower()
	if not extension in supported_extensions() and not path.begins_with("content://"): error="지원하는 이미지 확장자가 아닙니다"; return null
	var input=IO.read_bytes(path,func(): return cancelled)
	if input.has("error"): error=input.error; return null
	var data: PackedByteArray=input.bytes
	if extension=="gif" or gif_signature(data):
		var gif=decode_gif(data,true)
		if gif.is_empty(): return null
		return Image.create_from_data(gif.width,gif.height,false,Image.FORMAT_RGBA8,gif.frames[0].rgba)
	if not extension in NATIVE: return load_platform_image(data)
	var image=Image.new()
	var method="load_%s_from_buffer" % ("jpg" if extension=="jpeg" else extension)
	var result=ERR_UNAVAILABLE
	if image.has_method(method): result=image.call(method,data)
	elif extension=="hdr":
		# HDR has no buffer API in Godot 4.7. Opaque SAF URIs need a typed cache path.
		if path.begins_with("content://"):
			var cache="user://import-%d.hdr" % Time.get_ticks_usec()
			var output=FileAccess.open(cache,FileAccess.WRITE)
			if output==null: error="이미지 작업 공간을 만들지 못했습니다"; return null
			output.store_buffer(data); output.close(); result=image.load(cache); DirAccess.remove_absolute(cache)
		else: result=image.load(path)
	if result!=OK: error="이미지 디코딩에 실패했습니다"; return null
	decoder="Godot"
	return normalize(image)

func load_platform_image(_data: PackedByteArray) -> Image:
	error="지원하는 이미지 형식이 아닙니다"; return null

static func gif_signature(bytes: PackedByteArray) -> bool:
	return bytes.slice(0,6).get_string_from_ascii() in ["GIF87a","GIF89a"]
static func is_gif(path: String) -> bool:
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null: return false
	var signature=file.get_buffer(6); file.close()
	return gif_signature(signature)

func load_gif(path: String, first_only: bool = false) -> Dictionary:
	error=""; decoder=""
	var input=IO.read_bytes(path,func(): return cancelled)
	if input.has("error"): error=input.error; return {}
	return decode_gif(input.bytes,first_only)

func decode_gif(bytes: PackedByteArray, first_only: bool) -> Dictionary:
	if not ClassDB.class_exists("PapngGifDecoder"):
		error="내장 GIF 디코더가 없습니다. 전체 배포본을 사용하거나 소스의 네이티브 확장을 빌드하세요."; return {}
	var native=ClassDB.instantiate("PapngGifDecoder")
	var result: Dictionary=native.decode(bytes,first_only,func(): return cancelled)
	if result.has("error"): error=result.error; return {}
	decoder="giflib · 첫 이미지" if first_only else "giflib · GIF 애니메이션 %d프레임" % result.frames.size()
	result.decoder=decoder
	return result

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
