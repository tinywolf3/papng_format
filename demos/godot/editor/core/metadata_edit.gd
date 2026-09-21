extends RefCounted
## Replace one JSON5 value while preserving the source outside that value.
const Parser = preload("res://core/json5.gd")

static func encode(value: Variant, indent: String = "") -> String:
	if value is float and not is_finite(value): return "NaN" if is_nan(value) else "-Infinity" if value < 0 else "Infinity"
	if value is Dictionary:
		var parts = []
		for key in value: parts.append(indent+"  "+JSON.stringify(str(key))+": "+encode(value[key],indent+"  "))
		return "{\n"+",\n".join(parts)+"\n"+indent+"}" if not parts.is_empty() else "{}"
	if value is Array:
		var parts = []
		for item in value: parts.append(encode(item,indent+"  "))
		return "["+", ".join(parts)+"]"
	return JSON.stringify(value)

static func set_member(source: String, key: String, value: Variant) -> String:
	if source.strip_edges().is_empty(): source = "{schema_version: 1}"
	var parser = Parser.new()
	var obj = parser.parse(source)
	if not parser.error.is_empty() or not obj is Dictionary: return ""
	parser.pos = 0; parser.space(); parser.pos += 1; parser.space()
	var has_members = false
	var trailing_comma = false
	while parser.peek() != "}":
		has_members = true
		var name = parser.string_value(parser.peek()) if parser.peek() in ["'",'"'] else parser.bare()
		parser.space(); parser.pos += 1; parser.space()
		var start = parser.pos
		parser.value(1)
		var end = parser.pos
		if name == key: return source.left(start)+encode(value)+source.substr(end)
		parser.space()
		trailing_comma = parser.peek() == ","
		if not trailing_comma: break
		parser.pos += 1; parser.space()
	parser.space()
	var prefix = "" if not has_members or trailing_comma else ","
	return source.left(parser.pos)+prefix+"\n  "+JSON.stringify(key)+": "+encode(value)+"\n"+source.substr(parser.pos)
