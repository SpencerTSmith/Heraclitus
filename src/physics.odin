package main

// Hmm might go union route for this?
// Physics_Hull :: union {
//   AABB,
//   Sphere,
// }

// NOTE: Lots of this comes straight from the book Real-Time Collision Detection

PHYSICS_EPSILON :: 0.00001

AABB :: struct
{
  min: vec3,
  max: vec3,
}

Sphere :: struct
{
  center: vec3,
  radius: f32,
}

Ray :: struct
{
  origin:    vec3,
  direction: vec3, // Normalized
}

Plane :: struct
{
  normal:   vec3,
  d_origin: f32,
}

Vector :: struct
{
  origin:    vec3,
  direction: vec3, // Not necessarily normalized
}

Frustum_Face :: enum
{
  TOP,
  BOTTOM,
  LEFT,
  RIGHT,
  NEAR,
  FAR,
}
Frustum :: distinct [Frustum_Face]Plane

// NOTE: w/h aspect ratio.
make_frustum :: proc(camera: Camera, aspect_ratio, z_near, z_far: f32) -> (frustum: Frustum)
{
  forward, up, right := get_camera_axes(camera)

  // Half the width of the vertical axis of view
  half_v_side := z_far * tan(camera.curr_fov_y * 0.5)
  // Half the width of the horizontal axis of view
  half_h_side := aspect_ratio * half_v_side

  near_forward := z_near * forward
  far_forward  := z_far * forward

  // Self explanatory I think, normals point into the frustum
  frustum[.NEAR] = make_plane(forward, camera.position + near_forward)
  frustum[.FAR]  = make_plane(-forward, camera.position + far_forward)

  // These do have a point at the camera position since they converge there
  // As well, the far_forward +- camera_dir * aspect (which is the vector parallel to the plane),
  // crossed with the other camera direction will give the normal
  frustum[.RIGHT]  = make_plane(cross(up, far_forward + right * half_h_side), camera.position)
  frustum[.LEFT]   = make_plane(cross(far_forward - right * half_h_side, up), camera.position)
  frustum[.TOP]    = make_plane(cross(far_forward + up * half_v_side, right), camera.position)
  frustum[.BOTTOM] = make_plane(cross(right, far_forward - up * half_v_side), camera.position)

  return frustum
}

sphere_inside_plane :: proc(sphere: Sphere, plane: Plane) -> (inside: bool)
{
  // Project the sphere point onto the normal, subtract how far the plane actually is from world origin
  distance_to_plane := dot(plane.normal, sphere.center) - plane.d_origin

  // If the center is closer to the plane than its -radius, its at least partially inside
  inside = distance_to_plane > -sphere.radius
  return inside
}

sphere_inside_frustum :: proc(sphere: Sphere, frustum: Frustum) -> (inside: bool)
{
  inside = true

  // Inside all frustum planes
  for plane in frustum
  {
    if !sphere_inside_plane(sphere, plane)
    {
      inside = false
      break
    }
  }

  return inside
}

make_sphere :: proc(aabb: AABB) -> (sphere: Sphere)
{
  sphere.center = aabb_center(aabb)
  sphere.radius = length(aabb.max - sphere.center)

  return sphere
}

// Normalizes direction for you
make_ray :: proc(origin: vec3, direction: vec3) -> (ray: Ray)
{
  ray =
  {
    origin    = origin,
    direction = normalize0(direction),
  }

  return ray
}

make_plane :: proc(normal, point: vec3) -> (plane: Plane)
{
  norm := normalize0(normal)
  plane =
  {
    normal   = norm,
    d_origin = dot(norm, point),
  }

  return plane
}

aabb_center:: proc(aabb: AABB) -> (center: vec3)
{
  center = (aabb.min + aabb.max) * 0.5

  return center
}

// A 3D AABB is an intersection of 3 'Slabs' really, so we just test if the ray overlaps
// ALL 3 'Slabs'
ray_intersects_aabb :: proc(ray: Ray, box: AABB) -> (intersects: bool, t_min: f32, point: vec3)
{
  t_max := F32_MAX // NOTE: Infinite ray
  t_min  = 0.0

  intersects = true
  for i in 0..<3
  {
    // Ray is parallel to this axis (element is 0)
    if abs(ray.direction[i]) < PHYSICS_EPSILON
    {
      // If the ray is a parallel to an axis and the origin is not in the box, we know
      // the ray can't possible intersect ever
      if ray.origin[i] < box.min[i] || ray.origin[i] > box.max[i]
      {
        intersects = false
        break
      }
    }
    else
    {
      inverse_dir := 1.0 / ray.direction[i]

      t1 := (box.min[i] - ray.origin[i]) * inverse_dir
      t2 := (box.max[i] - ray.origin[i]) * inverse_dir

      // Swap if needed so that t1 is the intersection with the nearest plane,
      // and t2 is with farthest
      if t1 > t2
      {
        t1, t2 = t2, t1
      }

      if t1 > t_min { t_min = t1 }
      if t2 < t_max { t_max = t2 } // Dang typo in the book, but makes sense... wanting to shrink the interval, not let it grow

      // We don't intersect anymore
      if t_min > t_max
      {
        intersects = false
        break
      }
    }
  }

  if intersects
  {
    point = ray.origin + ray.direction * t_min
  }

  return intersects, t_min, point
}

// Plane = dot(plane.origin - position, normal) = 0
// ray = R(t) = dir(t) + origin
// dot(plane.origin - r(t), plane.normal)
// dot(plane.origin - dir(t) + origin, plane_normal) = 0

// From Real Time Collsion Detection
ray_intersects_plane :: proc(ray: Ray, plane: Plane) -> (intersects: bool, t: f32, pos: vec3)
{
  t = (plane.d_origin - dot(plane.normal, ray.origin)) / dot(plane.normal, ray.direction)

  if t >= 0.0
  {
    pos = ray.origin + t * ray.direction
    intersects = true
  }

  return intersects, t, pos
}

// From real-time collision detection
closest_point_on_aabb :: proc(point: vec3, aabb: AABB) -> vec3
{
  // Clamp the closest point either to the given point (if its inside the box)
  // Or to a point on the edge/surface/vertex of the bounding box in each axis
  closest: vec3
  for p, idx in point
  {
    closest[idx] = clamp(p, aabb.min[idx], aabb.max[idx])
  }

  return closest
}

// From real-time-collision detection
sphere_intersects_aabb :: proc(sphere: Sphere, aabb: AABB) -> bool
{
  // Find the closest point on the aabb to sphere, then if the squared distance of that to the sphere's center is
  // less than the squared sphere's radius we know we are intersecting!
  closest_point := closest_point_on_aabb(sphere.center, aabb)

  dist := closest_point - sphere.center

  return dot(dist, dist) < sphere.radius * sphere.radius
}

// Factored out into a generic function since we use it elsewhere
box_corners :: proc(xyz_min, xyz_max: vec3) -> [8]vec3
{
  min := xyz_min
  max := xyz_max
  corners: [8]vec3 =
  {
    {min.x, min.y, min.z}, // 0 left, bottom, back
    {max.x, min.y, min.z}, // 1 right, bottom, back
    {max.x, max.y, min.z}, // 2 right, top, back
    {min.x, max.y, min.z}, // 3 left, top, back
    {min.x, max.y, max.z}, // 4 left, top, front
    {min.x, min.y, max.z}, // 5 left, bottom, front
    {max.x, min.y, max.z}, // 6 right, bottom, front
    {max.x, max.y, max.z}, // 7 right, top, front
  }

  return corners
}

aabb_corners :: proc(aabb: AABB) -> [8]vec3
{
  return box_corners(aabb.min, aabb.max)
}

aabb_minkowski_difference :: proc(a: AABB, b: AABB) -> AABB
{
  result: AABB =
  {
    min = a.min - b.max,
    max = a.max - b.min,
  }

  return result
}

aabb_min_penetration_vector :: proc(a: AABB, b:AABB) -> (vec: vec3)
{
  overlap_x := min(a.max.x, b.max.x) - max(a.min.x, b.min.x)
  overlap_y := min(a.max.y, b.max.y) - max(a.min.y, b.min.y)
  overlap_z := min(a.max.z, b.max.z) - max(a.min.z, b.min.z)

  // If any axes don't overlap than we aren't intersecting
  // and the min vector should be 0, usually before calling this function you will
  // have checked for intersection, but whatever
  if overlap_x >= 0 && overlap_y >= 0 && overlap_z >= 0
  {
    center_a := (a.min + a.max) / 2.0
    center_b := (b.min + b.max) / 2.0
    center_d := center_a - center_b // Need this to determine which way the penetration vector should point.

    min_overlap := overlap_x
    axis := 0 // x

    if overlap_y < min_overlap
    {
      min_overlap = overlap_y
      axis = 1
    }

    if overlap_z < min_overlap
    {
      min_overlap = overlap_z
      axis = 2
    }

    sign: f32 = 1.0 if center_d[axis] >= 0.0 else -1.0
    vec[axis] = min_overlap * sign
  }

  return vec
}

transform_aabb :: proc
{
  transform_aabb_matrix,
  transform_aabb_fast,
}

transform_aabb_matrix :: proc(aabb: AABB, transform: mat4) -> AABB
{
  corners := aabb_corners(aabb)

  for &c in corners
  {
    c = (transform * vec4_from_3(c)).xyz
  }

  min_v := vec3{F32_MAX, F32_MAX, F32_MAX}
  max_v := vec3{F32_MIN, F32_MIN, F32_MIN}

  for c in corners
  {
    min_v = vmin(min_v, c)
    max_v = vmax(max_v, c)
  }

  recalc: AABB =
  {
    min = min_v,
    max = max_v,
  }

  return recalc
}

// Basically the new aabb can be found by just finding the min and max extents only in the specific
// axis rotation that contributes... we can take advantage of this
transform_aabb_fast :: proc(aabb: AABB, translation, rotation, scale: vec3) -> AABB
{
  rotation_y := mat4_rotate(WORLD_UP,      radians(rotation.y))
  rotation_x := mat4_rotate(WORLD_RIGHT,   radians(rotation.x))
  rotation_z := mat4_rotate(WORLD_FORWARD, radians(rotation.z))

  rot := rotation_y * rotation_x * rotation_z * mat4_scale(scale)

  // From 'Real-Time Collision Detection'
  result: AABB
  // For each axis
  for c in 0..<3
  {
    // Do the translation transform first by setting it to the translation
    // effectively adding it in.
    result.min[c] = translation[c]
    result.max[c] = translation[c]

    // Now we rotate... for each component of the rotation in this axis we do the multiplication
    // Remembering that the min will be composed of the smallest outputs and the max will be composed of the largest
    for r in 0..<3
    {
      e := rot[c][r] * aabb.min[r]
      f := rot[c][r] * aabb.max[r]

      if e < f
      {
        result.min[c] += e
        result.max[c] += f
      }
      else
      {
        result.min[c] += f
        result.max[c] += e
      }
    }
  }

  return result
}

aabbs_intersect :: proc(a: AABB, b: AABB) -> bool
{
  intersects := (a.min.x <= b.max.x && a.max.x >= b.min.x) &&
                (a.min.y <= b.max.y && a.max.y >= b.min.y) &&
                (a.min.z <= b.max.z && a.max.z >= b.min.z)

  return intersects
}

aabb_intersect_point :: proc(a: AABB, p: vec3) -> bool
{
  intersects := (a.min.x <= p.x && a.max.x >= p.x) &&
                (a.min.y <= p.y && a.max.y >= p.y) &&
                (a.min.z <= p.z && a.max.z >= p.z)

  return intersects
}

orthonormal_axes :: proc(forward: vec3) -> (right, up: vec3)
{
  forw := normalize(forward) // Just in case

  // Pick a direction that is not parallel to forward
  tmp := WORLD_UP if abs(forw.x) > abs(forw.z) else WORLD_RIGHT

  right = normalize(cross(forw, tmp))
  up    = normalize(cross(right, forw))

  return right, up
}
