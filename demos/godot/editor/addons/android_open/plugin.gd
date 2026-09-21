@tool
extends EditorPlugin
class AndroidOpenExport extends EditorExportPlugin:
	func _get_name() -> String: return "PapngAndroidOpen"
	func _supports_platform(platform: EditorExportPlatform) -> bool: return platform is EditorExportPlatformAndroid
	func _get_android_manifest_activity_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return FileAccess.get_file_as_string("res://addons/android_open/intents.xml")
var exporter = AndroidOpenExport.new()
func _enter_tree(): add_export_plugin(exporter)
func _exit_tree(): remove_export_plugin(exporter)
