package main

import "core:fmt"

Editor_State :: struct {
  selected_entity: ^Entity,
}

@(private="file")
editor: Editor_State

draw_editor_ui :: proc() {
  editor.selected_entity = &state.entities[0]

  entity_text := fmt.tprintf("%v", editor.selected_entity^)

  x := f32(state.window.w) * 0.5
  y := f32(state.window.h) - f32(state.window.h) * 0.05

  draw_text_with_background(entity_text, state.default_font, x, y, YELLOW, align=.CENTER, padding=5.0)
}
