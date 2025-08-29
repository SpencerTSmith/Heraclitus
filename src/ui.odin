package main

// NOTE: Planning, not actually using this yet
// UI_MAX_WIDGETS         :: 256
// UI_MAX_DRAWS           :: 512
// UI_WIDGET_MAX_CHILDREN :: 8
//
// UI_State :: struct {
//   widgets: Array(UI_Widget, UI_MAX_WIDGETS), // Probably want a pool or fridge array generic eventually
//   draws:   Array(UI_Draw, UI_MAX_DRAWS),
// }
//
// UI_Widget_Flags :: enum {
//   DRAW_TEXT,
//   DRAW_BACKGROUND,
//   CLICKABLE,
// }
//
// // Units for size and position are screen coords in pixels
// UI_Widget :: struct {
//   flags: bit_set[UI_Widget_Flags],
//
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

UI_Results :: enum {
  HOVERED,
  CLICKED,
}

// UI_Draw :: struct {
//   // Optional
//   text:       string,
//   text_color: vec4,
//
//   quad:       Quad,
//   quad_color: vec4,
// }
//
// @(private="file")
// ui: UI_State
//
// // TODO: need to generate draw commands, not calling into the immediate rendering system directly
// // That way can rearrange draw order, and run through them all in order
//
// // TODO: Should text be a default arg?
// ui_make_widget :: proc(flags: bit_set[UI_Widget_Flags], pos: vec2,
//                        text: string = ""
//                       ) -> (the_widget: ^UI_Widget) {
//   PADDING :: 5.0
//
//   // TODO: Robustness
//   l, t, b, r, w, h: f32
//   if .DRAW_TEXT in flags {
//     l, t, b, r = text_draw_rect(text, state.default_font, pos.x, pos.y)
//   }
//
//   if .DRAW_BACKGROUND in flags {
//     l = l - PADDING
//     t = t - PADDING
//     w = w + PADDING * 2
//     h = h + PADDING * 2
//   }
//
//   array_add(&ui.widgets, UI_Widget {
//     flags        = flags,
//     rel_position = pos,
//     width        = w,
//     height       = h,
//   })
//   slice := array_slice(&ui.widgets)
//   the_widget = &slice[len(slice) - 1]
//
//
//
//   array_add(&ui.draws, UI_Draw {
//     text = text,
//     // text_color
//   })
//
//   return the_widget
// }
//
// ui_widget_absolute_rect :: proc(widget: UI_Widget) -> (l, t, b, r: f32) {
//
//   return
// }
//
// ui_widget_results :: proc(widget: UI_Widget) -> (results: bit_set[UI_Results]) {
//   // if mouse_in_rect(widget.rel_position)
//
//   if .CLICKABLE in widget.flags{
//     if .HOVERED in results && mouse_pressed(.LEFT) {
//       results |= {.CLICKED}
//     }
//   }
//
//   return nil
// }

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
