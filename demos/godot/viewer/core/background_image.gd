extends RefCounted
## Decode by file contents so Android document URIs need no filename extension.
const MAX_BYTES = 64*1024*1024
const MAX_PIXELS = 32*1024*1024
static func load_image(path: String) -> Dictionary:
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return {"error":"배경 파일을 읽을 수 없습니다. 파일 선택기로 다시 선택하세요."}
	if file.get_length() > MAX_BYTES: return {"error":"배경 파일은 64 MiB 이하여야 합니다."}
	var bytes = PackedByteArray()
	while bytes.size() <= MAX_BYTES:
		var chunk = file.get_buffer(mini(65536,MAX_BYTES+1-bytes.size()))
		if chunk.is_empty(): break
		bytes.append_array(chunk)
	file.close()
	if bytes.is_empty() or bytes.size() > MAX_BYTES: return {"error":"배경 파일이 비어 있거나 64 MiB를 초과합니다."}
	var image = Image.new(); var result = ERR_FILE_UNRECOGNIZED
	if bytes.slice(0,8) == PackedByteArray([137,80,78,71,13,10,26,10]): result = image.load_png_from_buffer(bytes)
	elif bytes.slice(0,3) == PackedByteArray([255,216,255]): result = image.load_jpg_from_buffer(bytes)
	elif bytes.slice(0,4).get_string_from_ascii() == "RIFF" and bytes.slice(8,12).get_string_from_ascii() == "WEBP": result = image.load_webp_from_buffer(bytes)
	elif bytes.slice(0,2).get_string_from_ascii() == "BM": result = image.load_bmp_from_buffer(bytes)
	elif bytes[0] in [9,10,13,32,60] or bytes.slice(0,3) == PackedByteArray([239,187,191]):
		if bytes.slice(0,4096).get_string_from_utf8().contains("<svg"): result = image.load_svg_from_buffer(bytes)
	if result != OK or image.is_empty(): return {"error":"배경은 PNG·JPEG·WebP·BMP·SVG를 지원합니다. 파일 형식과 내용을 확인하세요."}
	if image.get_width()*image.get_height() > MAX_PIXELS: return {"error":"배경 이미지는 32 메가픽셀 이하여야 합니다."}
	image.clear_mipmaps(); image.convert(Image.FORMAT_RGBA8)
	var original_size = image.get_size()
	# Bound the display texture while preserving coordinates in original-image pixels.
	var edge = maxi(original_size.x,original_size.y)
	if edge > 4096: image.resize(maxi(1,roundi(original_size.x*4096.0/edge)),maxi(1,roundi(original_size.y*4096.0/edge)),Image.INTERPOLATE_LANCZOS)
	return {"image":image,"size":Vector2(original_size),"error":""}
