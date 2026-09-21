extends RefCounted
## Small original line icons shared by desktop and touch toolbars.
const SHORTCUTS={"pencil":"B","erase":"E","fill":"G","pick":"I","select":"R","line":"L","rect":"U","mask":"M","socket":"K"}
const PATHS={
	"pencil":'<path d="m4 20 1-6L16 3l5 5-11 11-6 1m9-14 5 5M5 14l5 5"/>',
	"erase":'<path d="m3 14 10-10 8 8-8 8H9l-6-6m5-5 8 8M12 20h10"/>',
	"fill":'<path d="m4 11 7-7 8 8-7 7-8-8m4-9 7 7M3 12h16M20 14q-5 6 0 6t0-6"/>',
	"pick":'<path d="m14 4 6 6M17 3l4 4-4 4-4-4 4-4M14 8 4 18v3h3L17 11M7 16l3 3"/>',
	"select":'<rect x="3" y="3" width="18" height="18" stroke-dasharray="3 3"/>',
	"line":'<path d="m4 20 16-16"/><circle cx="4" cy="20" r="2"/><circle cx="20" cy="4" r="2"/>',
	"rect":'<rect x="3" y="5" width="18" height="14"/>',
	"mask":'<path d="M3 4h18v8q0 7-9 10-9-3-9-10V4m9 0v18"/><path d="M12 5h8v7q0 5-8 8" fill="#89dcc4" stroke="none"/>',
	"socket":'<circle cx="12" cy="12" r="6"/><path d="M12 1v6m0 10v6M1 12h6m10 0h6"/><circle cx="12" cy="12" r="1"/>',
	"pan":'<path d="M12 2v20M2 12h20M8 6l4-4 4 4M8 18l4 4 4-4M6 8l-4 4 4 4m12-8 4 4-4 4"/>',
	"copy":'<rect x="8" y="8" width="13" height="13"/><path d="M5 16H3V3h13v2"/>',
	"cut":'<circle cx="5" cy="6" r="3"/><circle cx="5" cy="18" r="3"/><path d="m7 8 14 13M7 16 21 3"/>',
	"paste":'<path d="M8 5H4v16h16V5h-4"/><rect x="8" y="2" width="8" height="5"/><path d="M8 12h8m-8 4h6"/>',
	"clear":'<path d="m4 4 16 16M20 4 4 20"/>',
	"apply":'<path d="m3 12 6 6L21 5"/>',
	"undo":'<path d="m8 4-5 5 5 5M3 9h11a7 7 0 0 1 0 14"/>',
	"redo":'<path d="m16 4 5 5-5 5m5-5H10a7 7 0 0 0 0 14"/>',
	"menu":'<path d="M3 5h18M3 12h18M3 19h18"/>',
	"save":'<path d="M3 3h15l3 3v15H3V3m4 0v6h10V3M7 21v-8h10v8"/>',
	"frames":'<rect x="3" y="3" width="18" height="18"/><path d="M7 3v18M17 3v18M3 8h4m-4 8h4M17 8h4m-4 8h4"/>',
	"settings":'<path d="M3 6h18M3 12h18M3 18h18"/><circle cx="8" cy="6" r="2" fill="#33414e"/><circle cx="16" cy="12" r="2" fill="#33414e"/><circle cx="9" cy="18" r="2" fill="#33414e"/>',
	"play":'<path d="m7 3 14 9-14 9V3"/>',
	"plus":'<path d="M12 3v18M3 12h18"/>',
	"fit":'<path d="M3 9V3h6m6 0h6v6M3 15v6h6m6 0h6v-6"/>',
}
static var cache: Dictionary={}
static func texture(key: String) -> Texture2D:
	if not cache.has(key):
		var image=Image.new()
		image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#d9e7ef" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+PATHS.get(key,PATHS.settings)+'</g></svg>')
		cache[key]=ImageTexture.create_from_image(image)
	return cache[key]
static func button(parent: Node, key: String, label: String, action: Callable, shortcut: String = "") -> Button:
	var item=Button.new(); item.icon=texture(key); item.text=shortcut
	item.tooltip_text=label+(" ("+shortcut+")" if not shortcut.is_empty() else "")
	item.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER; item.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
	item.custom_minimum_size=Vector2(48,54 if not shortcut.is_empty() else 48)
	item.add_theme_constant_override("h_separation",2); item.add_theme_font_size_override("font_size",11)
	item.pressed.connect(action); parent.add_child(item); return item
