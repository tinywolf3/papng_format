extends RefCounted
## A bounded read shared by document, image and GIF loading, including SAF streams.
const LIMIT = 128*1024*1024
static func read_bytes(path: String, cancel: Callable = Callable(), limit: int = LIMIT) -> Dictionary:
	if cancel.is_valid() and cancel.call(): return {"error":"불러오기 취소"}
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null: return {"error":"파일을 열 수 없습니다: "+path}
	if file.get_length()>limit: file.close(); return {"error":"파일이 128 MiB 입력 예산을 초과합니다"}
	# Some document providers cannot report a length. Never use it as the EOF signal.
	var bytes=PackedByteArray()
	while true:
		if cancel.is_valid() and cancel.call(): file.close(); return {"error":"불러오기 취소"}
		var part=file.get_buffer(mini(65536,limit+1-bytes.size()))
		var failure=file.get_error()
		if failure!=OK and failure!=ERR_FILE_EOF: file.close(); return {"error":"파일을 읽지 못했습니다"}
		bytes.append_array(part)
		if bytes.size()>limit: file.close(); return {"error":"파일이 128 MiB 입력 예산을 초과합니다"}
		if part.is_empty(): break
	file.close()
	if bytes.is_empty(): return {"error":"파일이 비어 있습니다"}
	return {"bytes":bytes}
