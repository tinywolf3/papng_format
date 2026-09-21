extends "res://core/document.gd"
func decode(frame: int) -> PackedByteArray: return frames[frame].rgba
func mask(frame: int) -> PackedByteArray: return frames[frame].mask
