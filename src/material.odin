package main

import "core:log"
import "core:strings"
import "core:math"

import gl "vendor:OpenGL"
import stbi "vendor:stb/image"


// TODO: Unify texture creation under 1 function group would be nice
Texture_Type :: enum
{
  NONE,
  _2D,
  CUBE,
  CUBE_ARRAY,
}

Sampler_Preset :: enum
{
  NONE,
  REPEAT_TRILINEAR,
  REPEAT_LINEAR,
  CLAMP_LINEAR,
  CLAMP_WHITE,
}

Texture :: struct
{
  id:     u32,
  handle: u64,

  type:    Texture_Type,
  width:   int,
  height:  int,
  samples: int, // Only for multisampled textures, 0 if not
  depth:   int, // Only for array textures, 0 if not
  format:  Pixel_Format,
  sampler: Sampler_Preset,
}

Pixel_Format :: enum u32
{
  NONE,
  R8,
  RGB8,
  RGBA8,

  // Non linear color spaces, diffuse only, usually
  SRGB8,
  SRGBA8,

  RGBA16F,

  // Depth
  DEPTH32,
  DEPTH24_STENCIL8,
}

Material_Blend_Mode :: enum u32
{
  OPAQUE = 0,
  BLEND,
  MASK,
}

// TODO: Considering this more deeply, the 'Material' struct is, after some refactors, a very intermediate result
// It is not stored anywhere, with the *_Uniform containing everything gpu needs to know and *_Info for cpu.
Material :: struct
{
  buffer_index: u32, // Filled out upon upload

  diffuse:  Texture_Handle,
  specular: Texture_Handle,
  emissive: Texture_Handle,
  normal:   Texture_Handle,

  shininess: f32,

  blend: Material_Blend_Mode,
}

make_samplers :: proc() -> (samplers: [Sampler_Preset]u32)
{
  gl.CreateSamplers(len(samplers), &samplers[.NONE])

  gl.SamplerParameteri(samplers[.REPEAT_TRILINEAR], gl.TEXTURE_WRAP_S,     gl.REPEAT)
  gl.SamplerParameteri(samplers[.REPEAT_TRILINEAR], gl.TEXTURE_WRAP_T,     gl.REPEAT)
  gl.SamplerParameteri(samplers[.REPEAT_TRILINEAR], gl.TEXTURE_WRAP_R,     gl.REPEAT)
  gl.SamplerParameteri(samplers[.REPEAT_TRILINEAR], gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
  gl.SamplerParameteri(samplers[.REPEAT_TRILINEAR], gl.TEXTURE_MAG_FILTER, gl.LINEAR)

  gl.SamplerParameteri(samplers[.REPEAT_LINEAR], gl.TEXTURE_WRAP_S,     gl.REPEAT)
  gl.SamplerParameteri(samplers[.REPEAT_LINEAR], gl.TEXTURE_WRAP_T,     gl.REPEAT)
  gl.SamplerParameteri(samplers[.REPEAT_LINEAR], gl.TEXTURE_WRAP_R,     gl.REPEAT)
  gl.SamplerParameteri(samplers[.REPEAT_LINEAR], gl.TEXTURE_MIN_FILTER, gl.LINEAR)
  gl.SamplerParameteri(samplers[.REPEAT_LINEAR], gl.TEXTURE_MAG_FILTER, gl.LINEAR)

  gl.SamplerParameteri(samplers[.CLAMP_LINEAR], gl.TEXTURE_WRAP_S,     gl.CLAMP_TO_EDGE)
  gl.SamplerParameteri(samplers[.CLAMP_LINEAR], gl.TEXTURE_WRAP_T,     gl.CLAMP_TO_EDGE)
  gl.SamplerParameteri(samplers[.CLAMP_LINEAR], gl.TEXTURE_WRAP_R,     gl.CLAMP_TO_EDGE)
  gl.SamplerParameteri(samplers[.CLAMP_LINEAR], gl.TEXTURE_MIN_FILTER, gl.LINEAR)
  gl.SamplerParameteri(samplers[.CLAMP_LINEAR], gl.TEXTURE_MAG_FILTER, gl.LINEAR)

  border_color := WHITE
  gl.SamplerParameteri(samplers[.CLAMP_WHITE], gl.TEXTURE_WRAP_S,     gl.CLAMP_TO_BORDER)
  gl.SamplerParameteri(samplers[.CLAMP_WHITE], gl.TEXTURE_WRAP_T,     gl.CLAMP_TO_BORDER)
  gl.SamplerParameteri(samplers[.CLAMP_WHITE], gl.TEXTURE_WRAP_R,     gl.CLAMP_TO_BORDER)
  gl.SamplerParameteri(samplers[.CLAMP_WHITE], gl.TEXTURE_MIN_FILTER, gl.LINEAR)
  gl.SamplerParameteri(samplers[.CLAMP_WHITE], gl.TEXTURE_MAG_FILTER, gl.LINEAR)
  gl.SamplerParameterfv(samplers[.CLAMP_WHITE], gl.TEXTURE_BORDER_COLOR, &border_color[0])

  return samplers
}

make_material :: proc
{
  make_material_from_files,
}

DIFFUSE_DEFAULT  :: "white.png"
SPECULAR_DEFAULT :: "white.png"
EMISSIVE_DEFAULT :: "black.png"
NORMAL_DEFAULT   :: "flat_normal.png"

// Can either pass in nothing for a particular texture path, or pass in an empty string to use defaults
make_material_from_files :: proc(diffuse_path  := DIFFUSE_DEFAULT,
                                 specular_path := SPECULAR_DEFAULT,
                                 emissive_path := EMISSIVE_DEFAULT,
                                 normal_path   := NORMAL_DEFAULT,
                                 shininess: f32 = 32.0,
                                 blend: Material_Blend_Mode = .OPAQUE,
                                 in_texture_dir: bool = false) -> (material: Material, ok: bool)
{
  // HACK: Quite ugly but I think this makes it a nicer interface
  resolve_path :: proc(argument, default: string, argument_in_dir: bool) -> (resolved: string, in_texture_dir: bool)
  {
    if argument == "" || argument == default {
      resolved       = default
      in_texture_dir = true
    } else {
      resolved       = argument
      in_texture_dir = argument_in_dir
    }

    return resolved, in_texture_dir
  }

  diffuse,  diffuse_in_dir  := resolve_path(diffuse_path,  DIFFUSE_DEFAULT,  in_texture_dir)
  specular, specular_in_dir := resolve_path(specular_path, SPECULAR_DEFAULT, in_texture_dir)
  emissive, emissive_in_dir := resolve_path(emissive_path, EMISSIVE_DEFAULT, in_texture_dir)
  normal,   normal_in_dir   := resolve_path(normal_path,   NORMAL_DEFAULT,   in_texture_dir)

  material.diffuse  = load_texture(diffuse, nonlinear_color = true, in_texture_dir = diffuse_in_dir)
  material.specular = load_texture(specular, in_texture_dir = specular_in_dir)
  material.emissive = load_texture(emissive, in_texture_dir = emissive_in_dir)
  material.normal   = load_texture(normal, in_texture_dir = normal_in_dir)
  material.shininess = shininess
  material.blend = blend

  return material, ok
}

free_material :: proc(material: ^Material)
{
  diffuse  := get_texture(material.diffuse)
  specular := get_texture(material.specular)
  emissive := get_texture(material.emissive)
  normal   := get_texture(material.normal)

  free_texture(diffuse)
  free_texture(specular)
  free_texture(emissive)
  free_texture(normal)
}

make_texture :: proc
{
  make_texture_from_data,
  make_texture_from_file,
  make_texture_from_missing,
}

// Ugly, so we know it's missing
make_texture_from_missing :: proc() -> (texture: Texture)
{
  texture, _ = make_texture_from_file("missing.png")
  return texture
}

free_texture :: proc(texture: ^Texture) {
  if texture != nil && texture.id != 0
  {
    if texture.handle != 0
    {
      gl.MakeTextureHandleNonResidentARB(texture.handle)
    }

    gl.DeleteTextures(1, &texture.id)

    texture^ = {}
  }
}

bind_texture :: proc
{
  bind_texture_slot,
  bind_texture_name,
}

bind_texture_slot :: proc(slot: u32, texture: Texture)
{
  if state.bound_textures[slot].id != texture.id
  {
    state.bound_textures[slot] = texture
    gl.BindTextureUnit(slot, texture.id)
    gl.BindSampler(slot, state.samplers[texture.sampler])
  }
}

bind_texture_name :: proc(name: string, texture: Texture)
{
  if name in state.current_shader.uniforms
  {
    slot := state.current_shader.uniforms[name].binding
    bind_texture_slot(u32(slot), texture)
  }
}

// First value is the internal format and the second is the logical format
// Ie you pass the first to TextureStorage and the second to TextureSubImage
@(private="file")
gl_pixel_format_table: [Pixel_Format][2]u32 =
{
  .NONE  = {0,        0},
  .R8    = {gl.R8,    gl.RED},
  .RGB8  = {gl.RGB8,  gl.RGB},
  .RGBA8 = {gl.RGBA8, gl.RGBA},

  // Non linear color spaces, diffuse only, usually
  .SRGB8  = {gl.SRGB8,        gl.RGB},
  .SRGBA8 = {gl.SRGB8_ALPHA8, gl.RGBA},

  .RGBA16F = {gl.RGBA16F, gl.RGBA},

  // Depth sturf
  .DEPTH32          = {gl.DEPTH_COMPONENT32, gl.DEPTH_COMPONENT},
  .DEPTH24_STENCIL8 = {gl.DEPTH24_STENCIL8,  gl.DEPTH_STENCIL},
}

@(private="file")
gl_texture_type_table: [Texture_Type]u32 =
{
  .NONE       = 0,
  ._2D        = gl.TEXTURE_2D,
  .CUBE       = gl.TEXTURE_CUBE_MAP,
  .CUBE_ARRAY = gl.TEXTURE_CUBE_MAP_ARRAY,
}


alloc_texture :: proc(type: Texture_Type, format: Pixel_Format, sampler: Sampler_Preset,
                      width, height: int, samples: int = 0, array_depth: int = 0) -> (texture: Texture)
{
  assert(width > 0 && height > 0)

  gl_internal := gl_pixel_format_table[format][0]
  gl_type     := gl_texture_type_table[type]

  if samples > 0
  {
    assert(type == ._2D) // HACK: Only 2D textures can be multisampled for now
    gl_type = gl.TEXTURE_2D_MULTISAMPLE
  }

  gl.CreateTextures(gl_type, 1, &texture.id)

  mip_level: i32 = 1
  if sampler == .REPEAT_TRILINEAR
  {
    mip_level = i32(math.log2(f32(max(width, height))) + 1)
  }

  switch type
  {
  case .NONE:
    log.error("Texture type cannont be none")
  case ._2D: fallthrough
  case .CUBE:
    if samples > 0
    {
      assert(type == ._2D)
      gl.TextureStorage2DMultisample(texture.id, i32(samples), gl_internal, i32(width), i32(height), gl.TRUE)
    }
    else
    {
      gl.TextureStorage2D(texture.id, mip_level, gl_internal, i32(width), i32(height))
    }
  case .CUBE_ARRAY:
    assert(array_depth > 0)
    // NOTE: Texture storage 3D takes the 'true' number of layers
    // ie for cube maps the array length needs to be multiplied by 6.
    cube_depth := array_depth * 6
    gl.TextureStorage3D(texture.id, mip_level, gl_internal, i32(width), i32(height), i32(cube_depth))
  }

  texture.width   = width
  texture.height  = height
  texture.type    = type
  texture.format  = format
  texture.sampler = sampler
  texture.samples = samples
  texture.depth   = array_depth

  return texture
}

make_texture_from_data :: proc(type: Texture_Type, format: Pixel_Format, sampler: Sampler_Preset,
                               datas: []rawptr, width, height: int, samples: int = 0) -> (texture: Texture)
{
  texture = alloc_texture(type, format, sampler, width, height, samples)

  if datas != nil
  {
    gl_format := gl_pixel_format_table[format][1]
    switch type
    {
    case .NONE:
      assert(false, "Texture type cannot be none")
    case ._2D:
      assert(len(datas) == 1)
      gl.TextureSubImage2D(texture.id, 0, 0, 0, i32(width), i32(height), gl_format, gl.UNSIGNED_BYTE, datas[0])
    case .CUBE:
      if type == .CUBE
      {
        for data, face in datas
        {
          gl.TextureSubImage3D(texture.id, 0, 0, 0, i32(face), i32(width), i32(height), 1, gl_format, gl.UNSIGNED_BYTE, data)
        }
      }
    case .CUBE_ARRAY:
      assert(false) // What da?
    }

    gl.GenerateTextureMipmap(texture.id)
  }

  // NOTE: Hardcoded siwzzle when just one byte to be opacity
  if format == .R8
  {
    swizzle := []i32{gl.ONE, gl.ONE, gl.ONE, gl.RED}
    gl.TextureParameteriv(texture.id, gl.TEXTURE_SWIZZLE_RGBA, raw_data(swizzle))
  }

  return texture
}

// Creates a handle, makes it resident, appends to the end of the texture_handles gpu_buffer, and returns its index
make_texture_bindless :: proc(texture: ^Texture)
{
  if texture.handle == 0 {
    texture.handle = gl.GetTextureSamplerHandleARB(texture.id, state.samplers[texture.sampler])
    gl.MakeTextureHandleResidentARB(texture.handle)
  }
  else
  {
    // log.infof("Texture: %v is already bindless.", texture.id)
  }
}

format_for_channels :: proc(channels: int, nonlinear_color: bool = false) -> Pixel_Format
{
  format: Pixel_Format
  switch channels
  {
  case 1:
    format = .R8
  case 3:
    format = .SRGB8 if nonlinear_color else .RGB8
  case 4:
    format = .SRGBA8 if nonlinear_color else .RGBA8
  }

  return format
}

get_image_data :: proc(file_path: string) -> (data: rawptr, width, height, channels: int)
{
  c_path := strings.clone_to_cstring(file_path, context.temp_allocator)

  w, h, c: i32
  data = stbi.load(c_path, &w, &h, &c, 0)

  if data == nil
  {
    log.errorf("Could not load texture \"%v\"\n", file_path)
  }

  width    = cast(int)w
  height   = cast(int)h
  channels = cast(int)c

  return data, width, height, channels
}

free_image_data :: proc(data: rawptr)
{
  stbi.image_free(data)
}

// Right, left, top, bottom, back, front... or
// +x,    -x,   +y,    -y,   +z,  -z
make_texture_cube_map :: proc(file_paths: [6]string, in_texture_dir: bool = true) -> (cube_map: Texture, ok: bool)
{
  ok = true

  datas: [6]rawptr
  width, height, channels: int
  for file_name, idx in file_paths
  {
    path := join_file_path({TEXTURE_DIR, file_name}, context.temp_allocator) if in_texture_dir else file_name

    data, w, h, c := get_image_data(path)
    if data != nil
    {
      // NOTE: these should all be the same
      assert(!(width != 0) || (width == w && height == h && channels == c))

      width  = w
      height = h
      channels = c

      datas[idx] = data
    }
    else
    {
      log.errorf("Could not load %v for cubemap\n", path)
      ok = false
      break
    }
  }

  if ok
  {
    format := format_for_channels(channels, nonlinear_color=true)

    cube_map = make_texture_from_data(.CUBE, format, .CLAMP_LINEAR, datas[:], width, height)

    // Clean up
    for data in datas
    {
      free_image_data(data)
    }
  }

  return cube_map, ok
}

make_texture_from_file :: proc(file_name: string, nonlinear_color: bool = false) -> (texture: Texture, ok: bool)
{
  data, w, h, channels := get_image_data(file_name)
  if data != nil
  {
    defer free_image_data(data)

    format := format_for_channels(channels, nonlinear_color)

    texture = make_texture_from_data(._2D, format, .REPEAT_TRILINEAR, {data}, w, h)
    ok = true
  }
  else
  {
    log.errorf("Could not load texture \"%v\"\n", file_name)
  }

  return texture, ok
}
