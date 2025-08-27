package main

// NOTE: Planning, not actually using this yet
// UI_MAX_WIDGETS         :: 256
// UI_WIDGET_MAX_CHILDREN :: 8
//
// UI_State :: struct {
//   widgets: Array(UI_Widget, UI_MAX_WIDGETS), // Probably want a pool or fridge array generic eventually
// }
//
// UI_Flags :: enum {
//   CLICKABLE,
// }
//
// // Units for size and position are screen coords in pixels
// UI_Widget :: struct {
//   rel_position: vec2, // Relative to the parent
//
//   width:  f32,
//   height: f32,
//
//   // TODO: Should be fine to do pointers? static array of all widgets, so no pointer invalidation to think about, we will see, may want to have
//   // handle with generations
//   parent:   ^UI_Widget,
//   children: Array(^UI_Widget, UI_WIDGET_MAX_CHILDREN),
// }

// TODO: need to generate draw commands, not calling into the immediate rendering system directly
// That way can rearrange draw order, and run through them all in order

UI_Results :: enum {
  HOVERED,
  CLICKED,
}

ui_button :: proc(text: string, pos: vec2) -> (results: bit_set[UI_Results]) {
  l, t, b, r := draw_text_with_background(text, state.default_font, pos.x, pos.y, padding=5.0)

  if mouse_in_rect(l, t, b, r) {
    results |= {.HOVERED}
    draw_text_with_background(text, state.default_font, pos.x, pos.y, text_color=RED, padding=5.0)
  }

  if .HOVERED in results && mouse_pressed(.LEFT) {
    results |= {.CLICKED}
  }

  return results
}
