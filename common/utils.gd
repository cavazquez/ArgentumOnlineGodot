extends RefCounted
class_name Utils

static func GetFilesInDirectory(path:String) -> Array[String]:
	var files:Array[String] = []
	var dir = DirAccess.open(path)
	
	if dir:
		dir.list_dir_begin()
		var fileName = dir.get_next()
		while fileName != "":
			if !dir.current_is_dir():
				files.append(fileName)
			fileName = dir.get_next()
		dir.list_dir_end()
	return files 

static func HeadingToVector(heading:int) -> Vector2:
	if(heading == Enums.Heading.East):
		return Vector2.RIGHT; 
	if(heading == Enums.Heading.North):
		return Vector2.UP; 
	if(heading == Enums.Heading.South):
		return Vector2.DOWN; 
	if(heading == Enums.Heading.West):
		return Vector2.LEFT;
	return Vector2.ZERO

static func VectorToHeading(vector:Vector2) -> int: 
	if(vector == Vector2.LEFT):
		return Enums.Heading.West
	if(vector == Vector2.RIGHT):
		return Enums.Heading.East
	if(vector == Vector2.UP):
		return Enums.Heading.North
	if(vector == Vector2.DOWN):
		return Enums.Heading.South
	
	if(vector == Vector2(-1, -1)):
		return Enums.Heading.West;
	if(vector == Vector2(-1, 1)):
		return Enums.Heading.West;
	if(vector == Vector2(1, -1)):
		return Enums.Heading.East;
	if(vector == Vector2(1, 1)):
		return Enums.Heading.East;

	return Enums.Heading.None; 
	
static func GetCameraBounds(camera:Camera2D) -> Rect2:
	return camera.get_canvas_transform().affine_inverse() * camera.get_viewport_rect()

static func Sgn(x:int) -> int:
	if x > 0:
		return 1
	if x < 0:
		return -1
	return 0
	
static func GetNickColor(nickColor:int, privileges:int) -> Color:
	if privileges == 0:
		if nickColor & Enums.NickColor.IeAtacable:
			return GameAssets.GetNickColor(49)
		else:
			if nickColor & Enums.NickColor.IeCriminal:
				return GameAssets.GetNickColor(50)
			else:
				return GameAssets.GetNickColor(49)
	else:
		return GameAssets.GetNickColor(privileges) 

static func GetUnicodeString(stream:StreamPeer) -> String:
	var size = stream.get_u16()
	if size > 0:
		var data:PackedByteArray = stream.get_data(size)[1]
		return data.get_string_from_ascii() 
	return ""
	
static func CanEncodeLatin1(text: String) -> bool:
	for index in text.length():
		if text.unicode_at(index) > 255:
			return false
	return true

static func Utf8ToLatin1(text:String) -> PackedByteArray:
	if not CanEncodeLatin1(text):
		return PackedByteArray()
	var latin1_bytes := PackedByteArray()
	for index in text.length():
		latin1_bytes.append(text.unicode_at(index))
	return latin1_bytes

static func PutUnicodeString(stream:StreamPeer, text:String) -> bool:
	if not CanEncodeLatin1(text) or text.length() > 65535:
		return false
	var data := Utf8ToLatin1(text)
	stream.put_u16(data.size())
	stream.put_data(data)
	return true

static func IsEmailValid(email:String) -> bool:
	var regex = RegEx.new();
	regex.compile("^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\\.[a-zA-Z0-9-.]+$");

	return regex.search(email) != null

static func LegalCharacter(text:String) -> bool:
	var code = text.unicode_at(0)
	if code == 8:
		return true
		
	if code < 32 || code == 44:
		return false
	
	if code > 126:
		return false
		
	if code in [34, 42, 47, 58, 60, 62, 63, 92, 124]:
		return false 
	return true
	
static func ShowAlertDialog(title:String, message:String, parent:Node) -> AcceptDialog:
	var dialog = AcceptDialog.new()
	ApplyDialogTheme(dialog)
	parent.add_child(dialog)
	
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.dialog_hide_on_ok = false;
	dialog.title = title;
	dialog.dialog_text = message;
	dialog.popup_centered();
	
	return dialog

static func ApplyDialogTheme(window: Window) -> void:
	if window.has_meta("pyao_dialog_theme"): return
	window.set_meta("pyao_dialog_theme", true)
	window.theme = window.theme.duplicate() if window.theme else Theme.new()
	window.theme.default_font_size = Global.dialogFontSize
	var update := func(value: int):
		if is_instance_valid(window): window.theme.default_font_size = value
	Global.dialog_font_size_changed.connect(update)
	window.tree_exiting.connect(func():
		if Global.dialog_font_size_changed.is_connected(update): Global.dialog_font_size_changed.disconnect(update))
