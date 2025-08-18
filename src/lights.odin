package main

Point_Light :: struct {
  position:    vec3,

  color:       vec4,

  radius:      f32,
  intensity:   f32,
  ambient:     f32,

  // shadows: bool,
}

Direction_Light :: struct {
  direction: vec3,

  color:     vec4,

  intensity: f32,
  ambient:   f32,
}

Spot_Light :: struct {
  position:     vec3,
  direction:    vec3,

  color:        vec4,

  radius:       f32,
  intensity:    f32,
  ambient:      f32,

  // Cosines
  inner_cutoff: f32,
  outer_cutoff: f32,
}
