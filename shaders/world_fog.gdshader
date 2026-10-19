shader_type canvas_item;
render_mode unshaded;
uniform vec2 viewport_size = vec2(544.0, 416.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 centered = (UV - vec2(0.5)) * viewport_size / min(viewport_size.x, viewport_size.y);
	float edge = smoothstep(0.34, 0.78, length(centered));
	COLOR = vec4(0.04, 0.06, 0.08, edge * intensity * 0.65);
}
