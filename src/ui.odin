package main

// NOTE: Planning, not actually using this yet
UI_MAX_WIDGETS         :: 256
UI_MAX_DRAWS           :: 512
UI_WIDGET_MAX_CHILDREN :: 8

// TODO: Either need to clear these data structures every frame or hash them some how if we want to cache them
UI_State :: struct {
  widgets: Array(UI_Widget, UI_MAX_WIDGETS), // Probably want a pool or fridge array generic eventually
  draws:   Array(UI_Draw, UI_MAX_DRAWS),

  current_parent: ^UI_Widget,
}

UI_Widget_Flags :: enum {
  DRAW_TEXT,
  DRAW_BACKGROUND,
  CLICKABLE,
  DRAGGABLE,
}

// Units for size and position are screen coords in pixels
UI_Widget :: struct {
  flags: bit_set[UI_Widget_Flags],

  rel_position: vec2, // Relative to the parent

  width:  f32,
  height: f32,

  // TODO: Should be fine to do pointers? static array of all widgets, so no pointer invalidation to think about, we will see, may want to have
  // handle with generations
  parent:   ^UI_Widget,
  children: Array(^UI_Widget, UI_WIDGET_MAX_CHILDREN),
}

// NOTE: It might be better to have these as flags
// But then we will no langer have the nice syntax of:
// if ui_button(...).clicked {}
UI_Results :: struct {
  clicked: bool,
  hovered: bool,
}

UI_Draw :: struct {
  // Optional
  text:       string,
  text_pos:   vec2,
  text_color: vec4,

  quad:       Quad,
  quad_color: vec4,
}

@(private="file")
ui: UI_State

// TODO: need to generate draw commands, not calling into the immediate rendering system directly
// That way can rearrange draw order, and run through them all in order

// TODO: Should text be a default arg?
make_ui_widget :: proc(flags: bit_set[UI_Widget_Flags], pos: vec2,
                       text: string) -> (the_widget: ^UI_Widget, results: UI_Results) {

  // TODO: Robustness, this won't work correctly if not drawing text
  l, t, b, r, w, h: f32
  if .DRAW_TEXT in flags {
    l, t, b, r = text_draw_rect(text, state.default_font, pos.x, pos.y)
  }

  if .DRAW_BACKGROUND in flags {
    PADDING :: 5.0

    l = l - PADDING
    t = t - PADDING
    w = r - l + PADDING
    h = b - t + PADDING
  }

  the_widget = array_add(&ui.widgets, UI_Widget {
    flags        = flags,
    rel_position = {l, t}, // Hmmmm
    width        = w,
    height       = h,
  })

  if .DRAGGABLE in flags {

  }

  // See the results first before we decide how to draw it... might not be good... need to think
  results = ui_widget_results(the_widget^)

  // Lots of stuff not configurable right now
  array_add(&ui.draws, UI_Draw {
    text = text,
    text_pos = pos,
    text_color = RED if results.hovered else WHITE,
    quad = {
      top_left = {l, t},
      width    = w,
      height   = h,
    },
    quad_color = DEFAULT_TEXT_BACKGROUND,
  })

  return the_widget, results
}

ui_widget_results :: proc(widget: UI_Widget) -> (results: UI_Results) {
  // FIXME: Once add in parents need to traverse up parents to calc real rect position
  ancestor := widget.parent
  l: f32
  t: f32
  for ancestor != nil {
    l += ancestor.rel_position.x
    t += ancestor.rel_position.y
  }

  l += widget.rel_position.x
  t += widget.rel_position.y
  b := t + widget.height
  r := l + widget.width

  if mouse_in_rect(l, t, b, r) {
    results.hovered = true
  }

  if .CLICKABLE in widget.flags {
    if results.hovered && mouse_pressed(.LEFT) {
      results.clicked = true
    }
  }

  return results
}

// Flushes all UI draw records to the immediate rendering system
draw_ui :: proc() {
  for d in array_slice(&ui.draws) {
    immediate_quad(d.quad.top_left, d.quad.width, d.quad.height, d.quad_color)
    draw_text(d.text, state.default_font, d.text_pos.x, d.text_pos.y, d.text_color)
  }

  array_clear(&ui.draws)
  array_clear(&ui.widgets)
}

ui_button :: proc(text: string, pos: vec2) -> (results: UI_Results) {
  _, results = make_ui_widget({.DRAW_TEXT, .DRAW_BACKGROUND, .CLICKABLE}, pos, text)

   return results
}
