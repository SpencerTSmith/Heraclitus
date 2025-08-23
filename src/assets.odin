package main

import "core:path/filepath"
import "core:log"

DATA_DIR    :: "data" + PATH_SLASH
MODEL_DIR   :: DATA_DIR + "models"   + PATH_SLASH
TEXTURE_DIR :: DATA_DIR + "textures" + PATH_SLASH

Model_Handle   :: distinct u32
Texture_Handle :: distinct u32


// TODO: If doing streaming, then assets data structure should be pool like
// As it stands handle is just an index into this array that never changes or shrinks
// TODO: Maybe it should just be name to handle? Not the full relative path?
Asset_Catalog :: struct($Type, $Handle: typeid) {
  path_to_handle: map[string]Handle,
  assets:         [dynamic]Type,
}

Assets :: struct {
  model_catalog:   Asset_Catalog(Model, Model_Handle),
  texture_catalog: Asset_Catalog(Texture, Texture_Handle),
}

@(private="file")
assets: Assets

init_assets :: proc(allocator := context.allocator) {
  MODEL_ASSET_COUNT :: 128 // Expected
  assets.model_catalog.path_to_handle = make(map[string]Model_Handle, allocator)
  reserve(&assets.model_catalog.path_to_handle, MODEL_ASSET_COUNT)
  assets.model_catalog.assets = make([dynamic]Model, allocator)
  reserve(&assets.model_catalog.assets, MODEL_ASSET_COUNT)

  TEXTURE_ASSET_COUNT :: 256 // Expected
  assets.texture_catalog.path_to_handle = make(map[string]Texture_Handle, allocator)
  reserve(&assets.texture_catalog.path_to_handle, TEXTURE_ASSET_COUNT)
  assets.texture_catalog.assets = make([dynamic]Texture, allocator)
  reserve(&assets.texture_catalog.assets, TEXTURE_ASSET_COUNT)

  // Probably will want these so might as well load them now
  load_texture("white.png")
  load_texture("black.png")
  load_texture("flat_normal.png")

  // In case we can't load something have these fallbacks
  _, ok := load_texture(FALLBACK_TEXTURE)
  assert(ok, "Big trouble if we can't even load the missing fallback texture!")
  _, ok = load_model(FALLBACK_MODEL)
  assert(ok, "Big trouble if we can't even load the missing fallback model!")
}

FALLBACK_TEXTURE :: "missing.png"
FALLBACK_MODEL :: "missing/BoxTextured.gltf"

get_fallback_texture_handle :: proc() -> Texture_Handle {
  assert(TEXTURE_DIR + FALLBACK_TEXTURE in assets.texture_catalog.path_to_handle)
  return assets.texture_catalog.path_to_handle[TEXTURE_DIR + FALLBACK_TEXTURE]
}

get_fallback_model_handle :: proc() -> Model_Handle {
  assert(MODEL_DIR + FALLBACK_MODEL in assets.model_catalog.path_to_handle)
  return assets.model_catalog.path_to_handle[TEXTURE_DIR + FALLBACK_TEXTURE]
}

free_assets :: proc() {
  for &model in assets.model_catalog.assets {
    free_model(&model)
  }
  delete(assets.model_catalog.path_to_handle)
  delete(assets.model_catalog.assets)

  for &texture in assets.texture_catalog.assets {
    free_texture(&texture)
  }
  delete(assets.texture_catalog.path_to_handle)
  delete(assets.texture_catalog.assets)
}

load_model :: proc(name: string) -> (handle: Model_Handle, ok: bool) {
  path := filepath.join({MODEL_DIR, name}, context.temp_allocator)

  // Already loaded
  if path in assets.model_catalog.path_to_handle {
    return assets.model_catalog.path_to_handle[path], true
  }

  // NOTE: For now individual assets are always allocated on permanent arena
  model: Model
  model, ok = make_model(path, state.perm_alloc)

  if !ok {
    log.errorf("Model: %v unable to be loaded", path)
    handle = get_fallback_model_handle()
  } else {
    handle = cast(Model_Handle) len(assets.model_catalog.assets)
    append(&assets.model_catalog.assets, model)
    assets.model_catalog.path_to_handle[path] = handle
  }

  return handle, ok
}

get_model :: proc(handle: Model_Handle) -> ^Model {
  return &assets.model_catalog.assets[handle]
}

load_texture :: proc(name: string, nonlinear_color: bool = false,
                     in_texture_dir: bool = true) -> (handle: Texture_Handle, ok: bool) {
  path := filepath.join({TEXTURE_DIR, name}, context.temp_allocator) if in_texture_dir else name

  // Already loaded
  if path in assets.texture_catalog.path_to_handle {
    return assets.texture_catalog.path_to_handle[path], true
  }

  texture: Texture
  texture, ok = make_texture(path, nonlinear_color)

  if !ok {
    log.errorf("Texture: %v unable to be loaded", path)
    handle = get_fallback_texture_handle()
  } else {
    handle = cast(Texture_Handle) len(assets.texture_catalog.assets)
    append(&assets.texture_catalog.assets, texture)
    assets.texture_catalog.path_to_handle[path] = handle
  }


  return handle, ok
}

get_texture :: proc {
  get_texture_by_handle,
  get_texture_by_name,
}

get_texture_by_handle :: proc(handle: Texture_Handle) -> ^Texture {
  return &assets.texture_catalog.assets[handle]
}

get_texture_by_name :: proc(name: string) -> (texture: ^Texture) {
  // HACK: Maybe handle hashing should just hash the name, not the path, so don't have to do this business
  path := filepath.join({TEXTURE_DIR, name}, context.temp_allocator)

  // Already loaded
  if path in assets.texture_catalog.path_to_handle {
    texture = get_texture(assets.texture_catalog.path_to_handle[path])
  } else {
    // Load it if not already
    handle, ok := load_texture(name)
    if ok {
      texture = get_texture(handle)
    } else {
      // NOTE: Really should not be using this function often, so not going to bother with robust error handling yet
    }
  }

  return texture
}
