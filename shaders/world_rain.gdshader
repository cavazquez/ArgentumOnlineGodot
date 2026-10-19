shader_type canvas_item;
render_mode unshaded;
uniform vec2 viewport_size = vec2(544.0, 416.0);
uniform vec2 world_offset = vec2(0.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 pixel = UV * viewport_size + world_offset * 0.18;
	float column = floor((pixel.x + pixel.y * 0.24) / 17.0);
	float seed = fract(sin(column * 127.1) * 43758.5453);
	float x = fract((pixel.x + pixel.y * 0.24) / 17.0);
	float y = fract(pixel.y / 130.0 + seed - TIME * (1.2 + seed * 0.5));
	float streak = (1.0 - smoothstep(0.015, 0.07, abs(x - seed))) * step(y, 0.18);
	COLOR = vec4(0.65, 0.78, 0.88, streak * intensity * 0.45);
}
