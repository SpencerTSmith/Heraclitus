package main

import "core:path/filepath"
import "core:log"

DATA_DIR    :: "data" + PATH_SLASH
MODEL_DIR   :: DATA_DIR + "models"   + PATH_SLASH
TEXTURE_DIR :: DATA_DIR + "textures" + PATH_SLASH

// HACK: We are kind of double hashing... hash the name, then into the hash table
// Just so only have to store u32 in entity structs
Model_Handle   :: distinct u32
Texture_Handle :: distinct u32

// TODO: If doing streaming, then assets data structure should be pool like
// As it stands handle is just an index into this array that never changes or shrinks
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

  handle = cast(Model_Handle) len(assets.model_catalog.assets)

  // NOTE: For now individual assets are always allocated on permanent arena
  model: Model
  model, ok = make_model(path, state.perm_alloc)

  if !ok {
    log.warnf("Model: %v unable to be loaded", path)
    model, ok = make_model(state.perm_alloc)
  }

  append(&assets.model_catalog.assets, model)
  assets.model_catalog.path_to_handle[path] = handle

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

  handle = cast(Texture_Handle) len(assets.texture_catalog.assets)

  // NOTE: For now individual assets are always allocated on permanent arena
  texture: Texture
  texture, ok = make_texture(path, nonlinear_color)

  if !ok {
    log.debugf("Texture: %v unable to be loaded", path)
    texture = make_texture_from_missing()
  }

  append(&assets.texture_catalog.assets, texture)
  assets.texture_catalog.path_to_handle[path] = handle

  return handle, ok
}

get_texture :: proc(handle: Texture_Handle) -> ^Texture {
  return &assets.texture_catalog.assets[handle]
}
