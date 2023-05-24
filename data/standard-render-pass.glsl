#section VERTEX_SHADER
#include (trial:trial trial::standard-environment-information)

#section FRAGMENT_SHADER
#include (trial:trial trial::standard-light-block)
#include (trial:trial trial::standard-material-block)
#include (trial:trial trial::standard-environment-information)
layout (location = 0) out vec4 f_color;
layout (location = 1) out vec3 f_normal;
uniform sampler2D[32] textures;

vec2 uv;
vec3 position;
vec3 normal;
vec4 color;

void standard_init();
vec4 standard_shade(in StandardLight light);
vec4 standard_mix(in vec4 upper, in vec4 lower);
void standard_finish();

#define NONE -1
#define ALBEDO 0
#define NORMAL 1
#define EMISSION 2
#define SPECULAR 3
#define METAL_ROUGH_OCCLUSION 3
#define METALLIC 4
#define ROUGHNESS 5
#define OCCLUSION 6

vec4 sample_texture(int id, vec2 uv){
  switch(id){
  case NONE: return vec4(0);
  case ALBEDO:
  case NORMAL:
  case SPECULAR:
  case METAL_ROUGH_OCCLUSION:
  case EMISSION: return texture(textures[material.textures[id]], uv);
  case METALLIC: return texture(textures[material.textures[METAL_ROUGH_OCCLUSION]], uv).xxxx;
  case ROUGHNESS: return texture(textures[material.textures[METAL_ROUGH_OCCLUSION]], uv).yyyy;
  case OCCLUSION: return texture(textures[material.textures[METAL_ROUGH_OCCLUSION]], uv).zzzz;
  default: return vec4(1,0,0,1);
  }
}

struct StandardLightData{
  vec3 direction;
  vec3 radiance;
}

float evaluate_light_attenuation(StandardLight light){
  float distance = length(light.position - position);
  return 1.0 / (light.attenuation_linear * distance + light.attenuation_quadratic * distance * distance);
}

StandardLightData evaluate_light_ambient(in StandardLight light){
  return StandardLightData(-normal,
                           light.color);
}

StandardLightData evaluate_light_point(in StandardLight light){
  return StadardLightData(normalize(light.position - position),
                          light.color * evaluate_light_attenuation(light));
}

StandardLightData evaluate_light_directional(in StandardLight light){
  return StandardLightData(light.direction,
                           light.color);
}

StandardLightData evaluate_light_spot(in StandardLight light){
  vec3 light_dir = normalize(light.position - position);
  float theta = dot(light_dir, -light.direction);
  float intensity = 0.0;
  if(light.outer_radius < theta){
    float eps = light.cutoff_radius - light.outer_radius;
    intensity = clamp((theta - light.outer_radius) / eps, 0.0, 1.0);
  }
  return StandardLightData(light_dir,
                           light.color * intensity * evaluate_light_attenuation(light));
}

StandardLightData evaluate_light(in StandardLight light){
  switch(light.type){
  case 0: return evaluate_light_ambient(light);
  case 1: return evaluate_light_point(light);
  case 2: return evaluate_light_directional(light);
  case 3: return evaluate_light_spot(light);
  default: return StandardLightData(-normal, vec3(0));
  }
}

void main(){
  standard_init();
  for(int light_idx = 0; light_idx<light_Count; ++light_idx){
    StandardLight light = lights[light_idx];
    vec4 local_color;
    color = standard_mix(standard_shade(light, local_color), color);
  }
  standard_finish();
  f_color = color;
  f_normal = normal;
}
