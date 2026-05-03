package main

import "core:log"
import "core:strings"

DATA_DIR    :: "data" + PATH_SLASH
MODEL_DIR   :: DATA_DIR + "models"   + PATH_SLASH
TEXTURE_DIR :: DATA_DIR + "textures" + PATH_SLASH

WHITE_TEXTURE: Texture_Handle

Model_Handle   :: distinct u32
Texture_Handle :: distinct u32

// TODO: LRU instead of simple array for keeping track

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

init_assets :: proc()
{
  // Nil handles
  register_texture({})
  register_model({})
}

load_default_assets :: proc()
{
  // Probably will want these so might as well load them now
  WHITE_TEXTURE = load_texture("white.png")
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

// NOTE: The load* should never really 'fail' even if they can't load the passed data, they at least return a valid fallback so can continue rendering
// without crashing... the fallbacks are ugly enough to be noticeable

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
      handle = register_model(model)
      assets.model_catalog.path_map[path] = handle
    }
    else
    {
      log.warnf("Model: %v unable to be loaded, using fallback model", path)
      handle = fallback_model_handle()
    }
  }

  return handle, ok
}

register_model :: proc(model: Model) -> (handle: Model_Handle)
{
  handle = cast(Model_Handle) len(assets.model_catalog.assets)
  append(&assets.model_catalog.assets, model)

  return handle
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
      handle = register_texture(texture)

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

// Sometimes want to add a texture without going through load texture path... i.e. loading fonts
register_texture :: proc(texture: Texture) -> (handle: Texture_Handle)
{
  handle = cast(Texture_Handle) len(assets.texture_catalog.assets)
  append(&assets.texture_catalog.assets, texture)

  return handle
}

get_texture :: proc(handle: Texture_Handle) -> ^Texture
{
  return &assets.texture_catalog.assets[handle]
}

load_skybox :: proc(file_paths: [6]string) -> (handle: Texture_Handle, ok: bool) #optional_ok
{
  texture: Texture
  texture, ok = make_texture_cube_map(file_paths)
  handle = register_texture(texture)

  return handle, ok
}
