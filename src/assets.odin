package main

import "base:runtime"
import "core:log"
import "core:strings"

DATA_DIR    :: "data" + PATH_SLASH
MODEL_DIR   :: DATA_DIR + "models"   + PATH_SLASH
TEXTURE_DIR :: DATA_DIR + "textures" + PATH_SLASH

Model_Handle   :: distinct u32
Texture_Handle :: distinct u32

// TODO: If doing streaming, then assets data structure should be pool like
// As it stands handle is just an index into this array that never changes or shrinks

// TODO: Maybe it should just be name to handle? Not the full relative path?
Asset_Catalog :: struct($Type, $Handle: typeid, $N: int)
{
  path_map: map[string]Handle,
  assets:   [dynamic; N]Type,
}

// TODO: Probably should have its own memory arena
Assets :: struct
{
  model_catalog:   Asset_Catalog(Model, Model_Handle, 32),
  texture_catalog: Asset_Catalog(Texture, Texture_Handle, 256),
}

@(private="file")
assets: Assets

init_assets :: proc(allocator: runtime.Allocator)
{
  // Probably will want these so might as well load them now
  load_texture("white.png")
  load_texture("black.png")
  load_texture("flat_normal.png")

  // In case we can't load something have these fallbacks
  load_texture(FALLBACK_TEXTURE)
  load_model(FALLBACK_MODEL)
}

FALLBACK_TEXTURE :: "missing.png"
FALLBACK_MODEL   :: "missing/BoxTextured.gltf"

fallback_texture_handle :: proc() -> Texture_Handle
{
  assert(TEXTURE_DIR + FALLBACK_TEXTURE in assets.texture_catalog.path_map)
  return assets.texture_catalog.path_map[TEXTURE_DIR + FALLBACK_TEXTURE]
}

fallback_model_handle :: proc() -> Model_Handle
{
  assert(MODEL_DIR + FALLBACK_MODEL in assets.model_catalog.path_map)
  return assets.model_catalog.path_map[MODEL_DIR + FALLBACK_MODEL]
}

free_assets :: proc()
{
  for &model in assets.model_catalog.assets
  {
    free_model(&model)
  }
  delete(assets.model_catalog.path_map)

  for &texture in assets.texture_catalog.assets
  {
    free_texture(&texture)
  }
  delete(assets.texture_catalog.path_map)
}

load_model :: proc(name: string) -> (handle: Model_Handle, ok: bool) #optional_ok
{
  // Start by keeping the string on temp
  path := join_file_path({MODEL_DIR, name}, context.temp_allocator)

  // Already loaded
  if path in assets.model_catalog.path_map
  {
    handle = assets.model_catalog.path_map[path]
    ok = true
  }
  else
  {
    // Save the path for checking later, but only the first time.
    path = strings.clone(path, state.perm_alloc)

    model: Model
    model, ok = make_model(path, state.perm_alloc)

    if ok
    {
      handle = cast(Model_Handle) len(assets.model_catalog.assets)
      append(&assets.model_catalog.assets, model)
      assets.model_catalog.path_map[path] = handle
    }
    else
    {
      log.errorf("Model: %v unable to be loaded, using fallback model", path)
      handle = fallback_model_handle()
    }
  }

  return handle, ok
}

// Should always give valid pointer since give out fallback handles if we can't load a model.
get_model :: proc(handle: Model_Handle) -> ^Model
{
  return &assets.model_catalog.assets[handle]
}

load_texture :: proc(name: string, nonlinear_color: bool = false,
                     in_texture_dir: bool = true) -> (handle: Texture_Handle, ok: bool) #optional_ok
{
  path := join_file_path({TEXTURE_DIR, name}, context.temp_allocator) if in_texture_dir else name

  // Already loaded
  if path in assets.texture_catalog.path_map
  {
    handle = assets.texture_catalog.path_map[path]
    ok = true
  }
  else
  {
    texture: Texture
    texture, ok = make_texture(path, nonlinear_color)

    if ok
    {
      handle = register_texture(&texture)

      // Save the path for checking later, but only the first time.
      path = strings.clone(path, state.perm_alloc)

      assets.texture_catalog.path_map[path] = handle
    }
    else
    {
      log.errorf("Texture: %v unable to be loaded", path)
      handle = fallback_texture_handle()
    }
  }

  return handle, ok
}

// Sometimes want to add a texture without going through load texture path.
register_texture :: proc(texture: ^Texture) -> (handle: Texture_Handle)
{
  make_texture_bindless(texture)
  handle = cast(Texture_Handle) len(assets.texture_catalog.assets)
  append(&assets.texture_catalog.assets, texture^)

  return handle
}

get_texture :: proc
{
  get_texture_by_handle,
  get_texture_by_name,
}

get_texture_by_handle :: proc(handle: Texture_Handle) -> ^Texture
{
  return &assets.texture_catalog.assets[handle]
}

get_texture_by_name :: proc(name: string) -> (texture: ^Texture)
{
  path := join_file_path({TEXTURE_DIR, name}, context.temp_allocator) // Temp for checking, if we really need to load it... permanent alloc in load_texture

  // Already loaded
  if path in assets.texture_catalog.path_map
  {
    texture = get_texture(assets.texture_catalog.path_map[path])
  }
  else
  {
    log.infof("Loading Texture %v", name)
    // Load it if not already
    handle := load_texture(name)
    texture = get_texture(handle)
  }

  return texture
}

load_skybox :: proc(file_paths: [6]string) -> (handle: Texture_Handle, ok: bool)
{
  texture: Texture
  texture, ok = make_texture_cube_map(file_paths)
  handle = register_texture(&texture)

  return handle, ok
}
