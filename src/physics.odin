package main

import "core:math/linalg/glsl"
import "core:log"
import gl "vendor:OpenGL"

// Hmm might go union route for this?
// Physics_Hull :: union {
//   AABB,
//   Sphere,
// }

AABB :: struct {
  min: vec3,
  max: vec3,
}

Sphere :: struct {
  center: vec3,
  radius: f32,
}

sphere_intersects_aabb :: proc(sphere: Sphere, aabb: AABB) {

}

// Factored out into a generic function since we use it elsewhere
box_corners :: proc(xyz_min, xyz_max: vec3) -> [8]vec3 {
  min := xyz_min
  max := xyz_max
  corners := [8]vec3{
    {min.x, min.y, min.z}, // left, bottom, back
    {max.x, min.y, min.z}, // right, bottom, back
    {max.x, max.y, min.z}, // right, top, back
    {min.x, max.y, min.z}, // left, top, back
    {min.x, max.y, max.z}, // left, top, front
    {min.x, min.y, max.z}, // left, bottom, front
    {max.x, min.y, max.z}, // right, bottom, front
    {max.x, max.y, max.z}, // right, top, front
  }

  return corners
}

aabb_corners :: proc(aabb: AABB) -> [8]vec3 {
  return box_corners(aabb.min, aabb.max)
}

aabb_minkowski_difference :: proc(a: AABB, b: AABB) -> AABB {
  result: AABB = {
    min = a.min - b.max,
    max = a.max - b.min,
  }

  return result
}

aabb_min_penetration_vector :: proc(a: AABB, b:AABB) -> (vec: vec3) {
  overlap_x := min(a.max.x, b.max.x) - max(a.min.x, b.min.x)
  overlap_y := min(a.max.y, b.max.y) - max(a.min.y, b.min.y)
  overlap_z := min(a.max.z, b.max.z) - max(a.min.z, b.min.z)

  // If any axes don't overlap than we aren't intersecting
  // and the min vector should be 0, usually before calling this function you will
  // have checked for intersection, but whatever
  if overlap_x <= 0 || overlap_y <= 0 || overlap_z <= 0 {
    return vec
  }

  center_a := (a.min + a.max) / 2.0
  center_b := (b.min + b.max) / 2.0
  center_d := center_a - center_b // Need this to determine which way the penetration vector should point!

  min_overlap := overlap_x
  axis := 0 // x

  if overlap_y < min_overlap {
    min_overlap = overlap_y
    axis = 1
  }

  if overlap_z < min_overlap {
    min_overlap = overlap_z
    axis = 2
  }

  sign: f32 = 1.0 if center_d[axis] >= 0.0 else -1.0
  vec[axis] = min_overlap * sign

  return vec
}

transform_aabb :: proc {
  transform_aabb_matrix,
  transform_aabb_fast,
}

transform_aabb_matrix :: proc(aabb: AABB, transform: mat4) -> AABB {
  corners := aabb_corners(aabb)

  for &c in corners {
    c = (transform * vec4_from_3(c)).xyz
  }

  min_v := vec3{max(f32), max(f32), max(f32)}
  max_v := vec3{min(f32), min(f32), min(f32)}

  for c in corners {
    min_v = glsl.min(min_v, c)
    max_v = glsl.max(max_v, c)
  }

  recalc: AABB = {
    min = min_v,
    max = max_v,
  }

  return recalc
}

// Basically the new aabb can be found by just finding the min and max extents only in the specific
// axis rotation that contributes... we can take advantage of this
transform_aabb_fast :: proc(aabb: AABB, translation, rotation, scale: vec3) -> AABB {
  rotation_y := glsl.mat4Rotate({0.0, 1.0, 0.0}, glsl.radians_f32(rotation.y))
  rotation_x := glsl.mat4Rotate({1.0, 0.0, 0.0}, glsl.radians_f32(rotation.x))
  rotation_z := glsl.mat4Rotate({0.0, 0.0, 1.0}, glsl.radians_f32(rotation.z))

  rot := rotation_y * rotation_x * rotation_z * glsl.mat4Scale(scale)

  // From 'Real-Time Collision Detection'
  result: AABB
  // For each axis
  for c in 0..<3 {
    // Do the translation transform first by setting it to the translation
    // effectively adding it in.
    result.min[c] = translation[c]
    result.max[c] = translation[c]

    // Now we rotate... for each component of the rotation in this axis we do the multiplication
    // Remembering that the min will be composed of the smallest outputs and the max will be composed of the largest
    for r in 0..<3 {
      e := rot[c][r] * aabb.min[r]
      f := rot[c][r] * aabb.max[r]

      if (e < f) {
        result.min[c] += e
        result.max[c] += f
      } else {
        result.min[c] += f
        result.max[c] += e
      }
    }
  }

  return result
}

aabbs_intersect :: proc(a: AABB, b: AABB) -> bool {
  intersects := (a.min.x <= b.max.x && a.max.x >= b.min.x) &&
                (a.min.y <= b.max.y && a.max.y >= b.min.y) &&
                (a.min.z <= b.max.z && a.max.z >= b.min.z)

  return intersects
}

aabb_intersect_point :: proc(a: AABB, p: vec3) -> bool {
  intersects := (a.min.x <= p.x && a.max.x >= p.x) &&
                (a.min.y <= p.y && a.max.y >= p.y) &&
                (a.min.z <= p.z && a.max.z >= p.z)

  return intersects
}

draw_aabb :: proc(aabb: AABB, color: vec4 = GREEN) {
  immediate_box(aabb.min, aabb.max, color)
}
