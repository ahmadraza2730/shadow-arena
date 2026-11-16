shader_type spatial;
// Procedural brick wall. Uses world position, so any box gets bricks at a
// consistent real-world size with no UV unwrapping or texture files.

uniform vec3 brick_color : source_color = vec3(0.56, 0.27, 0.19);
uniform vec3 mortar_color : source_color = vec3(0.66, 0.62, 0.55);
uniform vec3 cap_color : source_color = vec3(0.6, 0.57, 0.52);
uniform vec2 brick_size = vec2(0.46, 0.15);   // metres: length, height
uniform float mortar = 0.014;                 // metres

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 n = abs(world_normal);
	if (n.y > 0.5) {
		// Top of the wall: plain concrete cap.
		ALBEDO = cap_color;
	} else {
		// Pick the wall plane, then lay bricks in a running bond.
		vec2 uv = n.x > 0.5 ? world_pos.zy : world_pos.xy;
		vec2 grid = uv / brick_size;
		float row = floor(grid.y);
		grid.x += mod(row, 2.0) * 0.5;
		vec2 cell = floor(grid);
		vec2 f = fract(grid);
		vec2 edge = vec2(mortar) / brick_size;
		float is_brick = step(edge.x, f.x) * step(edge.y, f.y);
		float shade = 0.78 + 0.4 * hash(cell);
		ALBEDO = mix(mortar_color, brick_color * shade, is_brick);
	}
	ROUGHNESS = 0.92;
}
