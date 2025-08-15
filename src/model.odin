package main

import "core:log"
import "core:slice"
import "core:strings"
import "core:path/filepath"

import "vendor:cgltf"
import gl "vendor:OpenGL"


Skybox :: struct {
  buffer:  GPU_Buffer,
  texture: Texture,
}

Mesh_Vertex :: struct {
  position: vec3,
  uv:       vec2,
  normal:   vec3,
  tangent:  vec4,
}

Mesh_Index :: distinct u32

// TODO: Seems not too bad to set this up as just 1 multi-draw indirect per model,
// instead of one regular draw per mesh, As well this may be more akin to a GLTF "primitive"
Mesh :: struct {
  vertex_count:   i32,
  index_offset:   i32,
  index_count:    i32,
  material_index: i32,

  aabb: AABB, // For each mesh... might do something diff... we will seeeeeee
}

// A model is composed of ONE vertex buffer containing both vertices and indices, vertices first, then indices
// at the right alignment, with "sub" meshes (gltf primitives like) that share the same material
Model :: struct {
  buffer:       GPU_Buffer,
  vertex_count: i32,
  index_count:  i32,

  // Triangle meshes, provide an index into a range of the overall buffer
  meshes:    []Mesh,
  materials: []Material,

  aabb: AABB, // For the model
}

make_model :: proc{
  make_model_from_file,
  make_model_from_data,
  make_model_from_default_white_cube,
  make_model_from_data_one_material_one_mesh,
}

// Takes in all vertices and all indices.. then a slice of the materials and a slice of the meshes
make_model_from_data :: proc(vertices: []Mesh_Vertex, indices: []Mesh_Index, materials: []Material, meshes: []Mesh) -> (model: Model, ok: bool) {
  buffer := make_vertex_buffer(Mesh_Vertex, len(vertices), len(indices), raw_data(vertices), raw_data(indices))

  //
  // Compute AABB
  //

  // HACK: GLTF Already gives you these I believe, perhaps doing unessecary work
  min_v := vec3{F32_MAX, F32_MAX, F32_MAX}
  max_v := vec3{F32_MIN, F32_MIN, F32_MIN}

  for v in vertices {
    min_v = vmin(min_v, v.position)
    max_v = vmax(max_v, v.position)
  }

  aabb: AABB = {
    min = min_v,
    max = max_v,
  }

  ok = true
  model = Model {
    buffer       = buffer,
    vertex_count = i32(len(vertices)),
    index_count  = i32(len(indices)),

    // Copying ugh, but hopefully ok
    meshes       = slice.clone(meshes, state.perm_alloc),
    materials    = slice.clone(materials, state.perm_alloc),

    aabb = aabb,
  }

  return model, ok
}

// TODO: Have a 'make_scene' proc to split nodes 'correctly' if I ever want that
// NOTE: Big assumptions:
// 1. This is one model (might not be an issue if just make that make_scene() proc)
// 2. That the image is always a separate image file (png, jpg, etc.)
make_model_from_file :: proc(file_name: string) -> (model: Model, ok: bool) {
  c_path := strings.clone_to_cstring(file_name, allocator = context.temp_allocator)

  dir := filepath.dir(file_name, context.temp_allocator)

  options: cgltf.options
  data, result := cgltf.parse_file(options, c_path)

  if result == .success && cgltf.load_buffers(options, data, c_path) == .success {
    defer cgltf.free(data)

    model_materials := make([dynamic]Material, allocator = context.temp_allocator)
    reserve(&model_materials, len(data.materials))


    // Collect materials
    for material in data.materials {
      diffuse_path: string
      if material.has_pbr_metallic_roughness &&
         material.pbr_metallic_roughness.base_color_texture.texture != nil {
        relative := string(material.pbr_metallic_roughness.base_color_texture.texture.image_.uri)

        diffuse_path = filepath.join({dir, relative}, allocator = context.temp_allocator)
      }

      specular_path:  string
      if material.has_specular &&
         material.specular.specular_texture.texture != nil {
        relative := string(material.specular.specular_texture.texture.image_.uri)

        specular_path = filepath.join({dir, relative}, allocator = context.temp_allocator)
      }

      emissive_path:  string
      if material.emissive_texture.texture != nil {
        relative := string(material.emissive_texture.texture.image_.uri)

        emissive_path = filepath.join({dir, relative}, allocator = context.temp_allocator)
      }

      normal_path: string
      if material.normal_texture.texture != nil {
        relative := string(material.normal_texture.texture.image_.uri)

        normal_path = filepath.join({dir, relative}, allocator = context.temp_allocator)
      }

      blend: Material_Blend_Mode
      switch material.alpha_mode {
      case .opaque:
        blend = .OPAQUE
      case .blend:
        blend = .BLEND
      case .mask:
        blend = .MASK
      }

      mesh_material := make_material(diffuse_path, specular_path, emissive_path, normal_path, blend = blend, in_texture_dir=false) or_return
      append(&model_materials, mesh_material)
    }

    // Each primitive will be its own mesh
    model_mesh_count: uint
    model_verts_count:  uint
    model_index_count:  uint

    // All nodes get loaded into the same model, we don't care about
    // GLTF's definition of a 'mesh' we care about the primitives which become our 'Mesh's
    for node in data.nodes {
      gltf_mesh := node.mesh

      // Only mesh nodes get put into the model
      if gltf_mesh == nil { continue }

      // Each primitive will became one of our 'Meshes'
      for primitive in gltf_mesh.primitives {
        if primitive.type != .triangles {
          log.warnf("Don't know how to handle Model: %v's primitive type: %v", file_name, primitive.type)
          continue
        }

        model_mesh_count += 1

        for attribute in primitive.attributes {
          if attribute.type == .position {
            model_verts_count += attribute.data.count
          }
        }

        if primitive.indices != nil {
          model_index_count += primitive.indices.count
        }
      }
    }

    model_meshes := make([dynamic]Mesh, allocator = context.temp_allocator)
    reserve(&model_meshes, len(data.meshes))

    model_verts := make([dynamic]Mesh_Vertex, allocator = context.temp_allocator)
    reserve(&model_verts, model_verts_count)

    model_index := make([dynamic]Mesh_Index,  allocator = context.temp_allocator)
    reserve(&model_index, model_index_count)

    for &node in data.nodes {
      gltf_mesh := node.mesh

      // Only mesh nodes get put into the model
      if gltf_mesh == nil { continue }

      node_world_transform: mat4
      cgltf.node_transform_world(&node, raw_data(&node_world_transform))

      // 3x3... normals aren't affected by translation
      node_world_normal_transform := inverse_transpose(mat3(node_world_transform))

      // Each primitive will became one of our 'Meshes'
      for primitive in gltf_mesh.primitives {
        if primitive.type != .triangles { continue } // Only triangle meshes

        position_access: ^cgltf.accessor
        normal_access:   ^cgltf.accessor
        tangent_access:  ^cgltf.accessor
        uv_access:       ^cgltf.accessor

        // Collect accessors for primitive
        for attribute in primitive.attributes {
          switch attribute.type {
          case .position:
            // Only vec3's
            if attribute.data.type == .vec3 && attribute.data.component_type == .r_32f {
              position_access = attribute.data
            } else {
              log.errorf("Model: %v has unsupported position attribute of type: %v", file_name, attribute.data.type)
            }
          case .normal:
            if attribute.data.type == .vec3 && attribute.data.component_type == .r_32f {
              normal_access = attribute.data
            } else {
              log.errorf("Model: %v has unsupported normal attribute of type: %v", file_name, attribute.data.type)
            }
          case .tangent:
            if attribute.data.type == .vec4 && attribute.data.component_type == .r_32f {
              tangent_access = attribute.data
            } else {
              log.errorf("Model: %v has unsupported tangent attribute of type: %v", file_name, attribute.data.type)
            }
          case .texcoord:
            if attribute.data.type == .vec2 && attribute.data.component_type == .r_32f {
              uv_access = attribute.data
            } else {
              log.errorf("Model: %v has unsupported uv attribute of type: %v", file_name, attribute.data.type)
            }
          case .invalid:
            fallthrough
          case .color:
            fallthrough
          case .joints:
            fallthrough
          case .weights:
            fallthrough
          case .custom:
            // log.warnf("Don't know how to handle this primitive attribute: %v\n", attribute.type)
          }
        }

        if position_access == nil ||
           normal_access   == nil ||
           uv_access       == nil {
          log.errorf("Model: %v unable to collect all NECESSARY attributes!", file_name)
          return
        }

        if position_access.count != normal_access.count ||
           position_access.count != uv_access.count     ||
           (tangent_access != nil && position_access.count != tangent_access.count) {
            log.warnf("Model: %v has mismatched vertex attribute counts", file_name)
        }

        primitive_vertex_count := position_access.count

        // Need to offset indices since we store all in the same vertex buffer!
        primitive_per_index_offset := len(model_verts)

        // We will also construct an AABB for each primitive
        mesh_aabb: AABB = {
          min = {max(f32), max(f32), max(f32)},
          max = {min(f32), min(f32), min(f32)},
        }

        //
        // Now actually make the new vertices
        //
        if position_access != nil &&
           normal_access   != nil &&
           uv_access       != nil {
          for i in 0..<primitive_vertex_count {
            new_vertex: Mesh_Vertex

            ok := cgltf.accessor_read_float(position_access, i, raw_data(&new_vertex.position), len(new_vertex.position))
            if !ok {
              log.warnf("Model: %v Trouble reading vertex position", file_name)
            }
            ok = cgltf.accessor_read_float(normal_access, i, raw_data(&new_vertex.normal), len(new_vertex.normal))
            if !ok {
              log.warnf("Model: %v Trouble reading vertex normal", file_name)
            }
            ok = cgltf.accessor_read_float(uv_access, i, raw_data(&new_vertex.uv), len(new_vertex.uv))
            if !ok {
              log.warnf("Model: %v Trouble reading vertex uv", file_name)
            }

            // NOTE: Not all meshes will have tangents! That's ok, we can compute our own so everything can go through the same shader!
            if tangent_access != nil {
              ok = cgltf.accessor_read_float(tangent_access, i, raw_data(&new_vertex.tangent), len(new_vertex.tangent))
              if !ok {
                log.warnf("Model: %v Trouble reading vertex tangent", file_name)
              }
            }

            // Transform the vertex by the node's world matrix! And same for the normals
            new_vertex.position = (node_world_transform * vec4_from_3(new_vertex.position)).xyz
            new_vertex.normal   = normalize(node_world_normal_transform * new_vertex.normal)

            // NOTE: Check this and make sure this works
            if tangent_access != nil {
              new_vertex.tangent.xyz = normalize(node_world_normal_transform * new_vertex.tangent.xyz)
            }

            // Collect AABB vertices
            mesh_aabb.min = vmin(mesh_aabb.min, new_vertex.position)
            mesh_aabb.max = vmax(mesh_aabb.max, new_vertex.position)

            append(&model_verts, new_vertex)
          }
        } else {
          log.errorf("Model: %v unable to collect all vertex accessors", file_name)
        }

        primitive_material_index := cgltf.material_index(data, primitive.material)
        primitive_index_count  := primitive.indices.count
        primitive_index_offset := len(model_index) // Before adding the indices!

        // Collect indices!
        if primitive.indices != nil && primitive.indices.buffer_view != nil {
          // Make sure that our index type matches up
          if primitive.indices.type            == .scalar &&
             (primitive.indices.component_type == .r_32u ||
              primitive.indices.component_type == .r_16u) {
            for i in 0..<primitive.indices.count {
              gltf_index := cgltf.accessor_read_index(primitive.indices, i)
              new_index := Mesh_Index(gltf_index + uint(primitive_per_index_offset))

              append(&model_index, new_index)
            }
          } else {
            log.errorf("Model: %v has unsupported index attribute of type: %v", file_name, primitive.indices.component_type)
          }
        }

        // NOTE: Alright now we can compute our own tangents for this primitive if we need to.
        // TODO: Save this so we don't have to do it everytime
        if tangent_access == nil {
          log.warnf("Model: %v Computing our own tangents", file_name)

          // Goin' through the primitive triangles and computing our tangents
          slice_start := uint(primitive_index_offset)
          slice_end   := slice_start + primitive_index_count

          assert(slice_end % 3 == 0, "Gotta be triangles, man.")

          for i := slice_start; i < slice_end; i += 3 {
            // Triangle
            idx0 := model_index[i + 0]
            idx1 := model_index[i + 1]
            idx2 := model_index[i + 2]

            // By pointer so we can accumulate the tangents back into them
            vert0 := &model_verts[idx0]
            vert1 := &model_verts[idx1]
            vert2 := &model_verts[idx2]

            // From LearnOpenGL, Linear equation to solve for tangent, can calc bitangent in vert shader as cross of normal and tangent
            edge0 := vert1.position - vert0.position
            edge1 := vert2.position - vert0.position

            delta_uv0 := vert1.uv - vert0.uv
            delta_uv1 := vert2.uv - vert0.uv

            denom := (delta_uv0.x * delta_uv1.y - delta_uv1.x * delta_uv0.y)
            f := 1.0 / denom

            tangent: vec4
            tangent.x = f * (delta_uv1.y * edge0.x - delta_uv0.y * edge1.x)
            tangent.y = f * (delta_uv1.y * edge0.y - delta_uv0.y * edge1.y)
            tangent.z = f * (delta_uv1.y * edge0.z - delta_uv0.y * edge1.z)

            vert0.tangent += tangent
            vert1.tangent += tangent
            vert2.tangent += tangent

            // Doin' redundant work, but that's ok probably, hopefully not may models won't come without tangents
            vert0.tangent.w = 1.0
            vert1.tangent.w = 1.0
            vert2.tangent.w = 1.0
          }
        }

        // NOTE: Hmm think i like the look of cast(T) better than the other way
        new_mesh := Mesh {
          vertex_count   = cast(i32)primitive_vertex_count,
          index_count    = cast(i32)primitive_index_count,
          index_offset   = cast(i32)primitive_index_offset,
          material_index = cast(i32)primitive_material_index,

          aabb = mesh_aabb,
        }

        append(&model_meshes, new_mesh)
      }
    }

    assert(len(model_verts) == cast(int) model_verts_count)
    assert(len(model_index) == cast(int) model_index_count)

    model, ok = make_model_from_data(model_verts[:], model_index[:], model_materials[:], model_meshes[:])
  } else do log.errorf("Unable to parse cgltf file \"%v\"\n", file_name)

  return model, ok
}

make_model_from_default_container :: proc() -> (model: Model, ok: bool) {
  mesh: Mesh = {
    material_index = 0,
    index_offset   = 0,
    index_count    = 36,
  }
  meshes: []Mesh = {mesh}
  material := make_material("container2.png", "container2_specular.png", shininess = 64.0, in_texture_dir=true) or_return
  materials: []Material = {material}

  model = make_model_from_data(DEFAULT_CUBE_VERT, DEFAULT_CUBE_INDX, materials, meshes) or_return
  return
}

make_model_from_default_white_cube :: proc() -> (model: Model, ok: bool) {
  mesh := Mesh {
    material_index = 0,
    index_offset   = 0,
    index_count    = 36,
  }
  meshes: []Mesh = {mesh}
  material := make_material(specular_path="black.png", in_texture_dir=true) or_return
  materials: []Material = {material}

  model = make_model_from_data(DEFAULT_CUBE_VERT, DEFAULT_CUBE_INDX, materials, meshes) or_return
  return
}

make_model_from_data_one_material_one_mesh :: proc(vertices: []Mesh_Vertex, indices: []Mesh_Index,
                                                   material: Material) -> (model: Model, ok: bool) {
  mesh := Mesh {
    index_count    = i32(len(indices)),
    index_offset   = 0,
    material_index = 0,
  }
  mesh_slice: []Mesh = {mesh}
  material_slice: []Material = {material}
  model, ok = make_model_from_data(vertices, indices, material_slice, mesh_slice)
  return
}

draw_model :: proc(model: Model, mul_color: vec4 = WHITE, instances: int = 1) {
  assert(state.current_shader.id != 0)

  bind_vertex_buffer(model.buffer)
  defer unbind_vertex_buffer()

  set_shader_uniform("mul_color", mul_color)

  for mesh in model.meshes {
    bind_material(model.materials[mesh.material_index])

    true_offset := i32(model.buffer.index_offset) + (mesh.index_offset * size_of(Mesh_Index))

    if instances > 1 {
      gl.DrawElementsInstanced(gl.TRIANGLES, mesh.index_count, gl.UNSIGNED_INT, rawptr(uintptr(true_offset)), i32(instances))
    } else {
      gl.DrawElements(gl.TRIANGLES, mesh.index_count, gl.UNSIGNED_INT, rawptr(uintptr(true_offset)))
    }
  }
}

model_has_transparency :: proc(model: Model) -> bool {
  for mat in model.materials {
    if mat.blend == .BLEND {
      return true
    }
  }

  return false
}

free_model :: proc(model: ^Model) {
  for &material in model.materials {
    free_material(&material)
  }
  free_gpu_buffer(&model.buffer)
}

// TODO: Make this work with the asset system
make_skybox :: proc(file_paths: [6]string) -> (skybox: Skybox, ok: bool) {
  skybox_verts := SKYBOX_VERTICES

  buffer  := make_vertex_buffer(vec3, len(skybox_verts), vertex_data = raw_data(skybox_verts))
  texture := make_texture_cube_map(file_paths) or_return

  skybox = {
    buffer  = buffer,
    texture = texture,
  }
  ok = true
  return skybox, ok
}

// Remember... binds the skybox shader
draw_skybox :: proc(skybox: Skybox) {
  bind_shader_program(state.shaders["skybox"])

  // Get the depth func before and reset after this call
  // TODO: Do this everywhere, ie push and pop GL state
  depth_func_before: i32; gl.GetIntegerv(gl.DEPTH_FUNC, &depth_func_before)
  gl.DepthFunc(gl.LEQUAL)
  defer gl.DepthFunc(u32(depth_func_before))

  bind_vertex_buffer(skybox.buffer)
  defer unbind_vertex_buffer()

  bind_texture(skybox.texture, "skybox")

  gl.DrawArrays(gl.TRIANGLES, 0, 36)
}

free_skybox :: proc(skybox: ^Skybox) {
  free_texture(&skybox.texture)
  free_gpu_buffer(&skybox.buffer)
}

SKYBOX_VERTICES :: []vec3{
  {-1.0,  1.0, -1.0},
  {-1.0, -1.0, -1.0},
  { 1.0, -1.0, -1.0},
  { 1.0, -1.0, -1.0},
  { 1.0,  1.0, -1.0},
  {-1.0,  1.0, -1.0},
  {-1.0, -1.0,  1.0},
  {-1.0, -1.0, -1.0},
  {-1.0,  1.0, -1.0},
  {-1.0,  1.0, -1.0},
  {-1.0,  1.0,  1.0},
  {-1.0, -1.0,  1.0},
  { 1.0, -1.0, -1.0},
  { 1.0, -1.0,  1.0},
  { 1.0,  1.0,  1.0},
  { 1.0,  1.0,  1.0},
  { 1.0,  1.0, -1.0},
  { 1.0, -1.0, -1.0},
  {-1.0, -1.0,  1.0},
  {-1.0,  1.0,  1.0},
  { 1.0,  1.0,  1.0},
  { 1.0,  1.0,  1.0},
  { 1.0, -1.0,  1.0},
  {-1.0, -1.0,  1.0},
  {-1.0,  1.0, -1.0},
  { 1.0,  1.0, -1.0},
  { 1.0,  1.0,  1.0},
  { 1.0,  1.0,  1.0},
  {-1.0,  1.0,  1.0},
  {-1.0,  1.0, -1.0},
  {-1.0, -1.0, -1.0},
  {-1.0, -1.0,  1.0},
  { 1.0, -1.0, -1.0},
  { 1.0, -1.0, -1.0},
  {-1.0, -1.0,  1.0},
  { 1.0, -1.0,  1.0},
}

DEFAULT_TRIANGLE_VERT :: []Mesh_Vertex {
  { position = {-0.5, -0.5, 0.0}}, // bottom right
  { position = { 0.5, -0.5, 0.0}}, // bottom left
  { position = { 0.0,  0.5, 0.0}}, // top
}

DEFAULT_SQUARE_VERT :: []Mesh_Vertex {
  { position = { 0.5,  0.5, 0.0}, uv = {1.0, 0.0}, normal = {0.0,  0.0, 1.0} }, // top right
  { position = { 0.5, -0.5, 0.0}, uv = {1.0, 1.0}, normal = {0.0,  0.0, 1.0} }, // bottom right
  { position = {-0.5, -0.5, 0.0}, uv = {0.0, 1.0}, normal = {0.0,  0.0, 1.0} }, // bottom left
  { position = {-0.5,  0.5, 0.0}, uv = {0.0, 0.0}, normal = {0.0,  0.0, 1.0} }, // top left
}

DEFAULT_SQUARE_INDX :: []Mesh_Index {
  3, 1, 0,   // first triangle
  3, 2, 1,   // second triangle
}

DEFAULT_CUBE_VERT :: []Mesh_Vertex {
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 0.0}, normal = { 0.0,  0.0, -1.0}, tangent = { 1.0,  0.0,  0.0, 1.0} },
  { position = { 0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = { 0.0,  0.0, -1.0}, tangent = { 1.0,  0.0,  0.0, 1.0} },
  { position = { 0.5, -0.5, -0.5}, uv = {1.0, 0.0}, normal = { 0.0,  0.0, -1.0}, tangent = { 1.0,  0.0,  0.0, 1.0} },
  { position = { 0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = { 0.0,  0.0, -1.0}, tangent = { 1.0,  0.0,  0.0, 1.0} },
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 0.0}, normal = { 0.0,  0.0, -1.0}, tangent = { 1.0,  0.0,  0.0, 1.0} },
  { position = {-0.5,  0.5, -0.5}, uv = {0.0, 1.0}, normal = { 0.0,  0.0, -1.0}, tangent = { 1.0,  0.0,  0.0, 1.0} },

  { position = {-0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = { 0.0,  0.0,  1.0}, tangent = {-1.0,  0.0,  0.0, 1.0} },
  { position = { 0.5, -0.5,  0.5}, uv = {1.0, 0.0}, normal = { 0.0,  0.0,  1.0}, tangent = {-1.0,  0.0,  0.0, 1.0} },
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 1.0}, normal = { 0.0,  0.0,  1.0}, tangent = {-1.0,  0.0,  0.0, 1.0} },
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 1.0}, normal = { 0.0,  0.0,  1.0}, tangent = {-1.0,  0.0,  0.0, 1.0} },
  { position = {-0.5,  0.5,  0.5}, uv = {0.0, 1.0}, normal = { 0.0,  0.0,  1.0}, tangent = {-1.0,  0.0,  0.0, 1.0} },
  { position = {-0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = { 0.0,  0.0,  1.0}, tangent = {-1.0,  0.0,  0.0, 1.0} },

  { position = {-0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = {-1.0,  0.0,  0.0}, tangent = { 0.0,  0.0, -1.0, 1.0} },
  { position = {-0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = {-1.0,  0.0,  0.0}, tangent = { 0.0,  0.0, -1.0, 1.0} },
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = {-1.0,  0.0,  0.0}, tangent = { 0.0,  0.0, -1.0, 1.0} },
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = {-1.0,  0.0,  0.0}, tangent = { 0.0,  0.0, -1.0, 1.0} },
  { position = {-0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = {-1.0,  0.0,  0.0}, tangent = { 0.0,  0.0, -1.0, 1.0} },
  { position = {-0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = {-1.0,  0.0,  0.0}, tangent = { 0.0,  0.0, -1.0, 1.0} },

  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = { 1.0,  0.0,  0.0}, tangent = { 0.0,  0.0,  1.0, 1.0} },
  { position = { 0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = { 1.0,  0.0,  0.0}, tangent = { 0.0,  0.0,  1.0, 1.0} },
  { position = { 0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = { 1.0,  0.0,  0.0}, tangent = { 0.0,  0.0,  1.0, 1.0} },
  { position = { 0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = { 1.0,  0.0,  0.0}, tangent = { 0.0,  0.0,  1.0, 1.0} },
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = { 1.0,  0.0,  0.0}, tangent = { 0.0,  0.0,  1.0, 1.0} },
  { position = { 0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = { 1.0,  0.0,  0.0}, tangent = { 0.0,  0.0,  1.0, 1.0} },

  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = { 0.0, -1.0,  0.0}, tangent = { 1.0,  0.0,  0.0, 1.0} },
  { position = { 0.5, -0.5, -0.5}, uv = {1.0, 1.0}, normal = { 0.0, -1.0,  0.0}, tangent = { 1.0,  0.0,  0.0, 1.0} },
  { position = { 0.5, -0.5,  0.5}, uv = {1.0, 0.0}, normal = { 0.0, -1.0,  0.0}, tangent = { 1.0,  0.0,  0.0, 1.0} },
  { position = { 0.5, -0.5,  0.5}, uv = {1.0, 0.0}, normal = { 0.0, -1.0,  0.0}, tangent = { 1.0,  0.0,  0.0, 1.0} },
  { position = {-0.5, -0.5,  0.5}, uv = {0.0, 0.0}, normal = { 0.0, -1.0,  0.0}, tangent = { 1.0,  0.0,  0.0, 1.0} },
  { position = {-0.5, -0.5, -0.5}, uv = {0.0, 1.0}, normal = { 0.0, -1.0,  0.0}, tangent = { 1.0,  0.0,  0.0, 1.0} },

  { position = {-0.5,  0.5, -0.5}, uv = {0.0, 1.0}, normal = { 0.0,  1.0,  0.0}, tangent = {-1.0,  0.0,  0.0, 1.0} },
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = { 0.0,  1.0,  0.0}, tangent = {-1.0,  0.0,  0.0, 1.0} },
  { position = { 0.5,  0.5, -0.5}, uv = {1.0, 1.0}, normal = { 0.0,  1.0,  0.0}, tangent = {-1.0,  0.0,  0.0, 1.0} },
  { position = { 0.5,  0.5,  0.5}, uv = {1.0, 0.0}, normal = { 0.0,  1.0,  0.0}, tangent = {-1.0,  0.0,  0.0, 1.0} },
  { position = {-0.5,  0.5, -0.5}, uv = {0.0, 1.0}, normal = { 0.0,  1.0,  0.0}, tangent = {-1.0,  0.0,  0.0, 1.0} },
  { position = {-0.5,  0.5,  0.5}, uv = {0.0, 0.0}, normal = { 0.0,  1.0,  0.0}, tangent = {-1.0,  0.0,  0.0, 1.0} },
}

DEFAULT_CUBE_INDX :: []Mesh_Index {
   0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17,
  18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,
}

DEFAULT_MODEL_POSITIONS :: []vec3 {
    { 0.0,  0.0,   0.0},
    { 2.0,  5.0, -15.0},
    {-1.5, -2.2,  -2.5},
    {-3.8, -2.0, -12.3},
    { 2.4, -0.4,  -3.5},
    {-1.7,  3.0,  -7.5},
    { 1.3, -2.0,  -2.5},
    { 1.5,  2.0,  -2.5},
    { 1.5,  0.2,  -1.5},
    {-1.3,  1.0,  -1.5},
}
