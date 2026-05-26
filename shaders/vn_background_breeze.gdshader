shader_type canvas_item;

uniform float water_strength = 0.0022;
uniform float grass_strength = 0.0035;
uniform float breeze_speed = 0.55;
uniform float shimmer_strength = 0.018;

void fragment() {
	vec2 uv = UV;

	float water_mask = smoothstep(0.30, 0.42, uv.y) * (1.0 - smoothstep(0.62, 0.74, uv.y));
	float grass_mask = smoothstep(0.52, 0.84, uv.y);

	float grass_wave = sin(uv.x * 28.0 + uv.y * 8.0 + TIME * breeze_speed * 2.4);
	grass_wave += sin(uv.x * 11.0 - TIME * breeze_speed * 1.7) * 0.45;

	float water_wave = sin(uv.y * 82.0 + TIME * breeze_speed * 3.2);
	water_wave *= sin(uv.x * 16.0 + TIME * breeze_speed * 1.6);

	vec2 offset = vec2(0.0);
	offset.x += grass_wave * grass_strength * grass_mask;
	offset.x += water_wave * water_strength * water_mask;
	offset.y += water_wave * water_strength * water_mask * 0.35;

	vec4 color = texture(TEXTURE, uv + offset);
	float shimmer = sin((uv.x + uv.y) * 70.0 + TIME * 1.6) * shimmer_strength * water_mask;
	color.rgb += shimmer;

	COLOR = color;
}
