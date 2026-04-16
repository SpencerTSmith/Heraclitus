package main
import "core:log"
import "core:strings"
import "core:math"

import stbi "vendor:stb/image"

Texture_Type :: enum u32
{
  NONE,
  D2,
  CUBE,
  CUBE_ARRAY,
}

Texture_Usage_Flag :: enum
{
  TARGET, // Could be used as a rendering attachment
}
Texture_Usage_Flags :: bit_set[Texture_Usage_Flag]

Sampler_Preset :: enum u32
{
  NONE,
  REPEAT_TRILINEAR,
  REPEAT_LINEAR,
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
  state:    Texture_State,

  type:        Texture_Type,
  width:       u32,
  height:      u32,
  samples:     u32, // Only for multisampled textures, 0 if not
  array_count: u32, // Only for array textures, 0 if not
  mip_count:   u32,
  format:      Pixel_Format,
  sampler:     Sampler_Preset,
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

make_samplers :: proc() -> (samplers: [Sampler_Preset]u32)
{

  return samplers
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

bind_texture :: proc
{
  bind_texture_to_slot,
  bind_texture_to_name,
  bind_texture_by_asset,
}

bind_texture_to_slot :: proc(slot: u32, texture: Texture)
{

}

bind_texture_to_name :: proc(name: string, texture: Texture)
{

}

bind_texture_by_asset :: proc(name: string, handle: Texture_Handle)
{
  texture := get_texture(handle)^
  bind_texture_to_name(name, texture)
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

  texture.internal = vk_alloc_texture(type, usage, format, sampler, width, height, samples, array_count, mip_count)
  texture.width    = width
  texture.height   = height
  texture.type     = type
  texture.format   = format
  texture.sampler  = sampler
  texture.samples  = samples
  texture.array_count = array_count
  texture.mip_count   = mip_count

  return texture
}

make_texture_from_data :: proc(type: Texture_Type, format: Pixel_Format, sampler: Sampler_Preset,
                               datas: []rawptr, width, height: u32, samples: u32 = 1) -> (texture: Texture)
{
  texture = alloc_texture(type, {}, format, sampler, width, height, samples)

  vk_upload_texture_data(state.renderer.staging_buffer[curr_frame_idx()], texture, datas[0])

  return texture
}

make_texture_bindless :: proc(texture: ^Texture)
{
}

format_for_channels :: proc(channels: u32, nonlinear_color: bool = false) -> Pixel_Format
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

get_image_data :: proc(file_path: string) -> (data: rawptr, width, height, channels: u32)
{
  c_path := strings.clone_to_cstring(file_path, context.temp_allocator)

  w, h, c: i32
  data = stbi.load(c_path, &w, &h, &c, 4)

  if data == nil
  {
    log.errorf("Could not load texture \"%v\".", file_path)
  }

  width    = cast(u32)w
  height   = cast(u32)h
  channels = 4 // NOTE: Force 4 channels

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
