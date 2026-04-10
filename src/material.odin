package main


Material_Blend_Mode :: enum u32
{
  OPAQUE, // Opaque by default, zero initialization
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
