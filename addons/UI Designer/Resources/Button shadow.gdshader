shader_type canvas_item;

varying vec4 color;

void vertex(){
	color = COLOR;
}

void fragment() {
	vec4 shadow = texture(TEXTURE, UV-vec2(0.1));
	shadow = vec4(vec3(0), shadow.a);
	COLOR = shadow + texture(TEXTURE, UV) * COLOR.a * color;
}
