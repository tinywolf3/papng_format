extends RefCounted
## JSON5 data parser. No expression evaluation. Duplicate decoded keys are errors.
var text = ""
var pos = 0
var error = ""
var identifier = RegEx.new()
var number = RegEx.new()

func parse(source: String) -> Variant:
	text = source
	pos = 0
	error = ""
	identifier.compile("^[$_\\p{L}\\p{Nl}\\x{2118}\\x{212E}\\x{309B}\\x{309C}][$_\\p{L}\\p{Nl}\\p{Mn}\\p{Mc}\\p{Nd}\\p{Pc}\\x{200C}\\x{200D}\\x{2118}\\x{212E}\\x{309B}\\x{309C}\\x{00B7}\\x{0387}\\x{1369}-\\x{1371}\\x{19DA}]*$")
	number.compile("^[+-]?(?:0[xX][0-9a-fA-F]+|(?:0|[1-9][0-9]*)(?:\\.[0-9]*)?(?:[eE][+-]?[0-9]+)?|\\.[0-9]+(?:[eE][+-]?[0-9]+)?|Infinity|NaN)$")
	if text.begins_with(String.chr(0xfeff)):
		fail("BOM은 허용하지 않습니다")
	var result = value(0)
	space()
	if pos != text.length():
		fail("후행 데이터")
	return result if error.is_empty() else null

func fail(message: String):
	if error.is_empty():
		error = "JSON5 위치 %d: %s" % [pos, message]

func peek() -> String:
	return text[pos] if pos < text.length() else ""

func white(c: String) -> bool:
	return not c.is_empty() and (c.unicode_at(0) in [9,10,11,12,13,32,160,0x1680,0x2028,0x2029,0x202f,0x205f,0x3000,0xfeff] or c.unicode_at(0) >= 0x2000 and c.unicode_at(0) <= 0x200a)

func space():
	while pos < text.length() and error.is_empty():
		if white(peek()):
			pos += 1
		elif text.substr(pos, 2) == "//":
			while pos < text.length() and not peek() in ["\n","\r",String.chr(0x2028),String.chr(0x2029)]:
				pos += 1
		elif text.substr(pos, 2) == "/*":
			var end = text.find("*/", pos + 2)
			if end < 0:
				fail("닫히지 않은 주석")
			else:
				pos = end + 2
		else:
			break

func hex_digits(count: int) -> int:
	var raw = text.substr(pos, count)
	pos += count
	if raw.length() != count or not raw.is_valid_hex_number(false):
		fail("잘못된 이스케이프")
		return 0
	return raw.hex_to_int()

func string_value(quote: String) -> String:
	pos += 1
	var result = ""
	while pos < text.length() and error.is_empty():
		var c = peek()
		pos += 1
		if c == quote:
			return result
		if c in ["\r", "\n"]:
			fail("문자열의 줄바꿈")
		elif c != "\\":
			result += c
		else:
			c = peek()
			pos += 1
			if c in ["\n", "\r", String.chr(0x2028), String.chr(0x2029)]:
				if c == "\r" and peek() == "\n":
					pos += 1
			elif c == "u" or c == "x":
				var code = hex_digits(4 if c == "u" else 2)
				if code >= 0xd800 and code <= 0xdbff and text.substr(pos, 2) == "\\u":
					pos += 2
					var low = hex_digits(4)
					if low < 0xdc00 or low > 0xdfff:
						fail("잘못된 유니코드 쌍")
					else:
						code = 0x10000 + ((code - 0xd800) << 10) + low - 0xdc00
				result += String.chr(code)
			elif c == "0":
				if peek() in ["0","1","2","3","4","5","6","7","8","9"]:
					fail("8진 이스케이프는 허용하지 않습니다")
				result += String.chr(0)
			elif c in ["1","2","3","4","5","6","7","8","9", ""]:
				fail("잘못된 문자열 이스케이프")
			else:
				result += {"b":"\b", "f":"\f", "n":"\n", "r":"\r", "t":"\t", "v":String.chr(11)}.get(c, c)
	fail("닫히지 않은 문자열")
	return result

func bare() -> String:
	var result = ""
	while pos < text.length() and not white(peek()) and not peek() in ["{","}","[","]",":",",","/", "'", '"']:
		if text.substr(pos, 2) == "\\u":
			pos += 2
			result += String.chr(hex_digits(4))
		else:
			result += peek()
			pos += 1
	return result

func value(depth: int) -> Variant:
	space()
	if depth >= 128 or not error.is_empty():
		fail("중첩 처리 예산 초과")
		return null
	var c = peek()
	if c == "'" or c == '"':
		return string_value(c)
	if c == "{" or c == "[":
		var object = c == "{"
		var end = "}" if object else "]"
		var result = {} if object else []
		pos += 1
		space()
		while peek() != end and error.is_empty():
			if object:
				var quoted = peek() in ["'", '"']
				var key = string_value(peek()) if quoted else bare()
				if (not quoted and identifier.search(key) == null) or result.has(key):
					fail("멤버 이름 오류 또는 중복 키")
				space()
				if peek() != ":":
					fail("콜론 누락")
				pos += 1
				result[key] = value(depth + 1)
			else:
				result.append(value(depth + 1))
			space()
			if peek() != ",":
				break
			pos += 1
			space()
		if peek() != end:
			fail("닫는 구분자 누락")
		pos += 1
		return result
	var start = pos
	var raw = bare()
	if text.substr(start, pos-start).contains("\\"):
		fail("값에는 식별자 이스케이프를 사용할 수 없습니다")
	if raw == "true": return true
	if raw == "false": return false
	if raw == "null": return null
	if number.search(raw) == null:
		fail("값 또는 숫자 문법 오류")
		return null
	var sign_value = -1 if raw.begins_with("-") else 1
	var unsigned = raw.trim_prefix("-").trim_prefix("+")
	if unsigned == "Infinity": return sign_value * INF
	if unsigned == "NaN": return NAN
	if unsigned.to_lower().begins_with("0x"): return sign_value * unsigned.hex_to_int()
	return raw.to_float()
