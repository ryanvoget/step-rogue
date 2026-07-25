shader_type canvas_item;

uniform float target_hue : hint_range(0.0, 1.0) = 0.583;
// When true, the shirt pixels are turned near-black instead of hue-shifted (used by the shop
// NPC — see shop_npc.gd — to distinguish it from the player).
uniform bool make_black = false;

vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (col.a >= 0.05) {
		vec3 hsv = rgb_to_hsv(col.rgb);
		// Blue shirt pixels sit in hue range 0.51–0.72 (185°–260°) with decent saturation
		if (hsv.x >= 0.51 && hsv.x <= 0.72 && hsv.y > 0.3) {
			if (make_black) {
				// Keep a little of the original shading so folds still read, but very dark.
				hsv.y = 0.0;
				hsv.z = hsv.z * 0.18;
			} else {
				hsv.x = target_hue;
			}
			col.rgb = hsv_to_rgb(hsv);
		}
	}
	COLOR = col;
}
