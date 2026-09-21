extends "res://core/import_image.gd"
## Android's platform decoder supplements Godot without an external executable.
const MAX_INPUT_BYTES=128*1024*1024
static func display_name(path: String) -> String:
	if not path.begins_with("content://") or OS.get_name()!="Android": return path.get_file()
	var runtime=Engine.get_singleton("AndroidRuntime")
	var uri=JavaClassWrapper.wrap("android.net.Uri").parse(path)
	var resolver=runtime.getActivity().getContentResolver()
	var cursor=resolver.query(uri,PackedStringArray(["_display_name"]),"",PackedStringArray(),"")
	var name="image"
	if cursor!=null:
		if cursor.moveToFirst(): name=str(cursor.getString(0))
		cursor.close()
	return name
func load_image(path: String) -> Image:
	if OS.get_name()!="Android": return super.load_image(path)
	error=""; decoder=""; cancelled=false
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null: error="선택한 문서에 접근할 수 없습니다. 파일 선택기로 다시 선택하세요."; return null
	if file.get_length()>MAX_INPUT_BYTES: file.close(); error="가져오기 파일이 128 MiB 처리 예산을 초과합니다."; return null
	var data=PackedByteArray()
	if file.get_length()>0: data=file.get_buffer(file.get_length())
	else:
		while data.size()<=MAX_INPUT_BYTES and not cancelled:
			var chunk=file.get_buffer(65536)
			if chunk.is_empty(): break
			data.append_array(chunk)
	file.close()
	if data.size()>MAX_INPUT_BYTES or data.is_empty(): error="이미지가 비어 있거나 너무 큽니다."; return null
	var extension=display_name(path).get_extension().to_lower()
	# File providers often return opaque URIs, not filename extensions.
	if extension in NATIVE:
		var cache="user://mobile-import."+extension
		var output=FileAccess.open(cache,FileAccess.WRITE)
		if output==null: error="이미지 작업 공간을 만들지 못했습니다."; return null
		output.store_buffer(data); output.close()
		var image=Image.new(); var result=image.load(cache); DirAccess.remove_absolute(cache)
		if result==OK and not image.is_empty():
			if image.is_compressed() and image.decompress()!=OK: error="압축 텍스처를 해제하지 못했습니다."; return null
			if image.get_width()*image.get_height()>32*1024*1024: error="이미지가 32 메가픽셀 처리 예산을 초과합니다."; return null
			image.clear_mipmaps(); image.convert(Image.FORMAT_RGBA8); decoder="Godot"; return image
	if cancelled: error="가져오기를 취소했습니다."; return null
	var factory=JavaClassWrapper.wrap("android.graphics.BitmapFactory")
	var options_class=JavaClassWrapper.wrap("android.graphics.BitmapFactory$Options")
	var options=options_class.call("BitmapFactory$Options")
	# JavaClassWrapper exposes methods and constants; mutable Java fields use reflection.
	var option_type=options.getClass(); var bounds=option_type.getField("inJustDecodeBounds")
	bounds.setBoolean(options,true)
	factory.decodeByteArray(data,0,data.size(),options)
	var width=option_type.getField("outWidth").getInt(options); var height=option_type.getField("outHeight").getInt(options)
	if width<=0 or height<=0:
		error="이 Android 기기에서 읽을 수 없는 이미지 형식입니다. PNG·JPEG·WebP로 변환해 가져오세요."; return null
	if width*height>32*1024*1024: error="이미지가 32 메가픽셀 처리 예산을 초과합니다."; return null
	bounds.setBoolean(options,false)
	var bitmap=factory.decodeByteArray(data,0,data.size(),options)
	if bitmap==null: error="Android 이미지 디코더가 파일을 읽지 못했습니다."; return null
	var stream=JavaClassWrapper.wrap("java.io.ByteArrayOutputStream").ByteArrayOutputStream()
	var ok=bitmap.compress(JavaClassWrapper.wrap("android.graphics.Bitmap$CompressFormat").valueOf("PNG"),100,stream)
	bitmap.recycle()
	if not ok: stream.close(); error="이미지를 변환하지 못했습니다."; return null
	var bytes: PackedByteArray=stream.toByteArray(); stream.close()
	var image=Image.new()
	if image.load_png_from_buffer(bytes)!=OK: error="변환한 이미지를 읽지 못했습니다."; return null
	image.convert(Image.FORMAT_RGBA8); decoder="Android · 첫 이미지"; return image
