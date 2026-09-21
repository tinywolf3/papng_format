extends RefCounted

var data: PackedByteArray
var pos = 0
var error = ""
static var crc_table: PackedInt64Array = []

func _init(bytes: PackedByteArray = PackedByteArray()):
	data = bytes

func take(n: int) -> PackedByteArray:
	if n < 0 or n > data.size() - pos:
		error = "잘린 바이너리 데이터"
		pos = data.size()
		return PackedByteArray()
	var result = data.slice(pos, pos + n)
	pos += n
	return result

func u(n: int) -> int:
	var bytes = take(n)
	var result: int = 0
	for byte in bytes:
		result = (result << 8) | byte
	return result

func signed(n: int) -> int:
	var value = u(n)
	return value - (1 << (8 * n)) if value & (1 << (8 * n - 1)) else value

static func be(value: int, size: int) -> PackedByteArray:
	var bytes = PackedByteArray()
	for i in range(size - 1, -1, -1):
		bytes.append((value >> (i * 8)) & 255)
	return bytes

static func crc(bytes: PackedByteArray) -> int:
	if crc_table.is_empty():
		for i in 256:
			var x = i
			for bit in 8:
				x = (x >> 1) ^ (0xedb88320 if x & 1 else 0)
			crc_table.append(x)
	var x: int = 0xffffffff
	for byte in bytes:
		x = crc_table[(x ^ byte) & 255] ^ (x >> 8)
	return x ^ 0xffffffff

static func chunk(name: String, bytes: PackedByteArray) -> PackedByteArray:
	var body = name.to_ascii_buffer() + bytes
	return be(bytes.size(), 4) + body + be(crc(body), 4)

# Verify zlib framing, consumption, Adler-32 and a decompression budget.
static func inflate(bytes: PackedByteArray, limit: int) -> PackedByteArray:
	if bytes.size() < 6 or bytes[0] & 15 != 8 or bytes[0] >> 4 > 7 or bytes[1] & 32 or (bytes[0] * 256 + bytes[1]) % 31:
		return PackedByteArray()
	var stream = StreamPeerGZIP.new()
	stream.start_decompression(true, 65536)
	var result = PackedByteArray()
	var offset = 0
	while offset < bytes.size():
		var part = stream.put_partial_data(bytes.slice(offset, mini(offset + 4096, bytes.size())))
		if part[0] != OK:
			return PackedByteArray()
		offset += part[1]
		var count = stream.get_available_bytes()
		if result.size() + count > limit or (part[1] == 0 and count == 0):
			return PackedByteArray()
		result.append_array(stream.get_data(count)[1])
	var a: int = 1
	var b: int = 0
	for value in result:
		a = (a + value) % 65521
		b = (b + a) % 65521
	var trailer: int = 0
	for value in bytes.slice(-4):
		trailer = (trailer << 8) | value
	return result if trailer == ((b << 16) | a) else PackedByteArray()
