package main
import "core:log"
import "core:strings"
import "core:math"

import vk "vendor:vulkan"
import stbi "vendor:stb/image"

// TODO: Unify texture creation under 1 function group would be nice
Texture_Type :: enum
{
  NONE,
  D2,
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
  image: vk.Image,
  view:  vk.ImageView,

  type:    Texture_Type,
  width:   u32,
  height:  u32,
  samples: u32, // Only for multisampled textures, 0 if not
  array_count: u32, // Only for array textures, 0 if not
  mip_count:   u32,
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
  vk.DestroyImage(vk_device(), texture.image, nil)
  vk.DestroyImageView(vk_device(), texture.view, nil)
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
  if name in state.current_shader.uniforms
  {
    slot := state.current_shader.uniforms[name].binding
    bind_texture_to_slot(u32(slot), texture)
  }
}

bind_texture_by_asset :: proc(name: string, handle: Texture_Handle)
{
  texture := get_texture(handle)^
  bind_texture_to_name(name, texture)
}

pixel_format_to_vk_aspects :: proc(format: Pixel_Format) -> (aspects: vk.ImageAspectFlags)
{
  switch format
  {
    case .NONE: assert(false)
    case .R8, .RGB8, .RGBA8, .SRGB8, .SRGBA8, .RGBA16F:
      aspects += {.COLOR}
    case .DEPTH24_STENCIL8:
      aspects += {.STENCIL}
      fallthrough
    case .DEPTH32:
      aspects += {.DEPTH}
  }

  return aspects
}

// First value is the internal format and the second is the logical format
// Ie you pass the first to TextureStorage and the second to TextureSubImage

// TODO: Cubemaps
alloc_texture :: proc(type: Texture_Type, format: Pixel_Format, sampler: Sampler_Preset,
                      width, height: u32, samples: u32 = 1, array_count: u32 = 1, is_render_target := false) -> (texture: Texture)
{
  assert(width > 0 && height > 0)

  vk_format_table: [Pixel_Format]vk.Format =
  {
    .NONE             = .UNDEFINED,
    .R8               = .R8_UNORM,
    .RGB8             = .R8G8B8_UNORM,
    .RGBA8            = .R8G8B8A8_UNORM,
    .SRGB8            = .R8G8B8_SRGB,
    .SRGBA8           = .R8G8B8A8_SRGB,
    .RGBA16F          = .R16G16B16A16_SFLOAT,
    .DEPTH32          = .D32_SFLOAT,
    .DEPTH24_STENCIL8 = .D24_UNORM_S8_UINT,
  }

  vk_samples: vk.SampleCountFlags
  switch samples
  {
    case:
      log.errorf("Invalid sample count requested for texture.")
      fallthrough // use 1 sample if invalid
    case 1: vk_samples = {._1}
    case 2: vk_samples = {._2}
    case 4: vk_samples = {._4}
    case 8: vk_samples = {._8}
  }

  mip_count: u32 = 1
  if sampler == .REPEAT_TRILINEAR
  {
    mip_count = u32(math.floor(math.log2(f64(max(width, height))))) + 1
  }

  usage: vk.ImageUsageFlags = {.TRANSFER_DST, .SAMPLED} // Always
  if mip_count > 1 { usage += {.TRANSFER_SRC} } // Will have to read to generate mips

  if is_render_target
  {
    usage += {.STORAGE, .TRANSFER_SRC}
    if format == .DEPTH32 || format == .DEPTH24_STENCIL8
    {
      usage += {.DEPTH_STENCIL_ATTACHMENT}
    }
    else
    {
      usage += {.COLOR_ATTACHMENT}
    }
  }

  flags: vk.ImageCreateFlags
  if type == .CUBE || type == .CUBE_ARRAY { flags |= {.CUBE_COMPATIBLE} }

  image_info: vk.ImageCreateInfo =
  {
    sType       = .IMAGE_CREATE_INFO,
    imageType   = .D2, // NOTE: Hardcoded.
    extent      = {width, height, 1}, // NOTE: Hardcoded.
    format      = vk_format_table[format],
    mipLevels   = mip_count, // TODO: Generate mipmaps.
    arrayLayers = array_count,
    samples     = vk_samples,
    tiling      = .OPTIMAL, // Currently not ever reading back textures sooo.
    usage       = usage,
  }

  vk_assert(vk.CreateImage(vk_device(), &image_info, nil, &texture.image),
            "Unable to create vulkan image.")

  vk_view_type_table: [Texture_Type]vk.ImageViewType =
  {
    .NONE = .D1, // Shouldn't happen
    .D2   = .D2,
    .CUBE = .CUBE,
    .CUBE_ARRAY = .CUBE,
  }

  components: vk.ComponentMapping = {.IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY} if format != .R8 else {.R, .R, .R, .R }

  vk_arena_push_image(.DEVICE, texture.image)

  view_info: vk.ImageViewCreateInfo =
  {
    sType      = .IMAGE_VIEW_CREATE_INFO,
    image      = texture.image,
    format     = image_info.format,
    viewType   = vk_view_type_table[type],
    components = components,
    subresourceRange = vk_image_range(pixel_format_to_vk_aspects(format), mip_count = mip_count,  array_count = array_count)
  }

  vk_assert(vk.CreateImageView(vk_device(), &view_info, nil, &texture.view),
            "Unable to create vulkan image view.")

  texture.width   = width
  texture.height  = height
  texture.type    = type
  texture.format  = format
  texture.sampler = sampler
  texture.samples = samples
  texture.array_count = array_count
  texture.mip_count   = mip_count

  return texture
}

// NOTE: Hardcoded to just blit everything entirely
blit_textures :: proc(src, dst: Texture, src_w, src_h, dst_w, dst_h: u32)
{
  blit_region :vk.ImageBlit2 =
  {
    sType = .IMAGE_BLIT_2,
    srcOffsets = {{0,0,0}, {i32(src_w), i32(src_h), 1}},
    srcSubresource =
    {
      aspectMask = pixel_format_to_vk_aspects(src.format),
      layerCount = src.array_count,
    },
    dstOffsets = {{0,0,0}, {i32(dst_w), i32(dst_h), 1}},
    dstSubresource =
    {
      aspectMask = pixel_format_to_vk_aspects(dst.format),
      layerCount = dst.array_count,
    },
  }

  blit_info: vk.BlitImageInfo2 =
  {
    sType          = .BLIT_IMAGE_INFO_2,
    srcImage       = src.image,
    srcImageLayout = .TRANSFER_SRC_OPTIMAL,
    dstImage       = dst.image,
    dstImageLayout = .TRANSFER_DST_OPTIMAL,
    filter         = .LINEAR,
    pRegions       = &blit_region,
    regionCount    = 1,
  }

  vk.CmdBlitImage2(vk_cmd(), &blit_info)
}

make_texture_from_data :: proc(type: Texture_Type, format: Pixel_Format, sampler: Sampler_Preset,
                               datas: []rawptr, width, height: u32, samples: u32 = 0) -> (texture: Texture)
{
  texture = alloc_texture(type, format, sampler, width, height, samples)

  return texture
}

// Creates a handle, makes it resident, appends to the end of the texture_handles gpu_buffer, and returns its index
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
  data = stbi.load(c_path, &w, &h, &c, 0)

  if data == nil
  {
    log.errorf("Could not load texture \"%v\".", file_path)
  }

  width    = cast(u32)w
  height   = cast(u32)h
  channels = cast(u32)c

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
