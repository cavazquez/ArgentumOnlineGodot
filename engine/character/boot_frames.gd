extends RefCounted
class_name BootFrames

# Original PNGs and animation indices: The Mana World, GPL-2.0 (see adjacent license).
const STYLES := ["", "furboots", "warlordboots", "bromenalboots", "assassin-boots", "furboots"]
const COLORS := [Color.WHITE, Color("ac8259"), Color.WHITE, Color("c09762"), Color("8d7baf"), Color("799fdd")]
static var _cache: Dictionary = {}

static func frames(id: int) -> SpriteFrames:
	if _cache.has(id): return _cache[id]
	var result := SpriteFrames.new()
	result.remove_animation("default")
	if id < 1 or id >= STYLES.size(): return result
	var atlas: Texture2D = load("res://Assets/Equipment/Boots/upstream/%s.png" % STYLES[id])
	var bases := {"south": 0, "west": 18, "north": 36, "east": 54}
	for direction in bases:
		for mode in ["idle", "walk"]:
			var key: String = mode + "_" + direction
			result.add_animation(key)
			result.set_animation_speed(key, 8)
			var indices := [bases[direction]] if mode == "idle" else range(bases[direction] + 1, bases[direction] + 7)
			for index in indices:
				var frame := AtlasTexture.new()
				frame.atlas = atlas
				frame.region = Rect2((index % 9) * 64, floori(index / 9.0) * 64, 64, 64)
				result.add_frame(key, frame)
	_cache[id] = result
	return result
