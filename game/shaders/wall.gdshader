shader_type spatial;
// Weathered concrete that dissolves (ordered dither) where it sits between the camera and
// the player, like Diablo 2 Resurrected's wall cutaway.

global uniform vec3 player_pos;
global uniform vec3 camera_pos;
uniform vec3 tint : source_color = vec3(0.45, 0.43, 0.4);
uniform sampler2D grime : source_color, filter_linear_mipmap, repeat_enable;
uniform float radius = 2.2;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 target = player_pos + vec3(0.0, 0.9, 0.0);
	vec3 seg = target - camera_pos;
	float t = dot(world_pos - camera_pos, seg) / dot(seg, seg);
	if (t > 0.0 && t < 0.96) {
		float d = length(camera_pos + seg * t - world_pos);
		float fade = smoothstep(radius, radius * 0.55, d);
		const float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
				3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		ivec2 p = ivec2(FRAGCOORD.xy) % 4;
		if (fade > (bayer[p.y * 4 + p.x] + 0.5) / 16.0) {
			discard;
		}
	}
	vec3 n = abs(NORMAL * mat3(VIEW_MATRIX));
	vec2 uv = n.y > 0.5 ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
	ALBEDO = tint * texture(grime, uv * 0.3).rgb * 1.6;
	ROUGHNESS = 0.95;
}
