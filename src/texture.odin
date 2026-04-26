package main

import "core:log"
import "core:strings"
import "core:math"
import "core:mem"

import stbi "vendor:stb/image"

Texture_Type :: enum u32
{
  D2,
  CUBE,
  CUBE_ARRAY,
}

@(rodata)
MAX_DESCRIPTORS: [Texture_Type]u32 =
{
  .D2         = 512,
  .CUBE       = 4, // Skyboxes
  .CUBE_ARRAY = 1, // Just for point light shadow maps.
}

@(rodata)
DESCRIPTOR_BINDING: [Texture_Type]u32 =
{
  .D2         = 0,
  .CUBE       = 1,
  .CUBE_ARRAY = 2, // Just for point light shadow maps.
}

Texture_Usage_Flag :: enum
{
  TARGET, // Could be used as a rendering attachment
}
Texture_Usage_Flags :: bit_set[Texture_Usage_Flag]

Sampler_Preset :: enum u32
{
  REPEAT_NEAREST,
  REPEAT_TRILINEAR, // Max anisotropy, too.
  CLAMP_LINEAR,
  CLAMP_WHITE,
}

Texture_State :: enum u32
{
  NONE,
  FRAGMENT_READ,
  TRANSFER_DST,
  TRANSFER_SRC,
  TARGET,
}

Texture :: struct
{
  internal: Renderer_Internal, // To get at the underlying api object details.
  index:    u32,  // Into descriptor set
  state:    Texture_State,

  type:        Texture_Type,
  width:       u32,
  height:      u32,
  samples:     u32, // Only for multisampled textures, 1 if not
  array_count: u32, // Only for array textures, 1 if not
  mip_count:   u32,
  format:      Pixel_Format,
  sampler:     Sampler_Preset,
}

Pixel_Format :: enum u32
{
  NONE,
  R8,
  RGBA8,
  SRGBA8,
  RGBA16F,
  DEPTH32,
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

free_texture :: proc(texture: ^Texture)
{
  // TODO: Not needed at this stage, since just using arena for everything.
  texture^ = {}
}

alloc_texture :: proc(type: Texture_Type, usage: Texture_Usage_Flags, format: Pixel_Format, sampler: Sampler_Preset,
                      width, height: u32, samples: u32 = 1, array_count: u32 = 1) -> (texture: Texture)
{
  assert(width > 0 && height > 0)
  mip_count: u32 = 1

  if sampler == .REPEAT_TRILINEAR
  {
    mip_count = u32(math.floor(math.log2(f64(max(width, height))))) + 1
  }

  array_count := array_count

  if type == .CUBE || type == .CUBE_ARRAY
  {
    array_count *= 6
  }

  texture.internal, texture.index = vk_alloc_texture(type, usage, format, sampler, width, height, samples, array_count, mip_count)
  texture.width       = width
  texture.height      = height
  texture.type        = type
  texture.format      = format
  texture.sampler     = sampler
  texture.samples     = samples
  texture.array_count = array_count
  texture.mip_count   = mip_count

  return texture
}

make_texture_from_data :: proc(type: Texture_Type, format: Pixel_Format, sampler: Sampler_Preset,
                               datas: [][]byte, width, height: u32, samples: u32 = 1) -> (texture: Texture)
{
  texture = alloc_texture(type, {}, format, sampler, width, height, samples)
  upload_texture(datas, texture)

  return texture
}

format_for_channels :: proc(channels: u32, nonlinear_color: bool = false) -> Pixel_Format
{
  format: Pixel_Format
  switch channels
  {
    case 1:
      format = .R8
    case 4:
      format = .SRGBA8 if nonlinear_color else .RGBA8
    case:
      unimplemented()
  }

  return format
}

get_image_data :: proc(file_path: string) -> (data: []byte, width, height, channels: u32)
{
  c_path := strings.clone_to_cstring(file_path, context.temp_allocator)

  w, h, c: i32
  stbi.info(c_path, &w, &h, &c)

  // GPUs generally don't actually support only 3 channels
  desired_c := 4 if c == 3 else c

  ptr := stbi.load(c_path, &w, &h, &c, desired_c)

  if ptr != nil
  {
    // I hope this fine, I would just rather pass byte slices than rawptrs.
    data = mem.byte_slice(ptr, w * h * desired_c * size_of(byte))
    width    = cast(u32)w
    height   = cast(u32)h
    channels = cast(u32)desired_c
  }
  else
  {
    log.errorf("Could not load texture \"%v\".", file_path)
  }

  return data, width, height, channels
}

free_image_data :: proc(data: []byte)
{
  stbi.image_free(raw_data(data))
}

// Right, left, top, bottom, back, front... or
// +x,    -x,   +y,    -y,   +z,  -z
make_texture_cube_map :: proc(file_paths: [6]string, in_texture_dir: bool = true) -> (cube_map: Texture, ok: bool)
{
  ok = true

  datas: [6][]byte
  width, height, channels: u32
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
      log.errorf("Could not load %v for cubemap.", path)
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

    texture = make_texture_from_data(.D2, format, .REPEAT_TRILINEAR, {data}, w, h)
    ok = true
  }
  else
  {
    log.errorf("Could make texture \"%v\".", file_name)
  }

  return texture, ok
}
