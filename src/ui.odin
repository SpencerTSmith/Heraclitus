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

  position: vec2, // Relative to the parent

  width:  f32,
  height: f32,

  // TODO: Should be fine to do pointers? static array of all widgets, so no pointer invalidation to think about, we will see, may want to have
  // handle with generations
  parent:   ^UI_Widget,
  children: Array(^UI_Widget, UI_WIDGET_MAX_CHILDREN),
  child_padding: f32, // Space between children
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

calc_ui_absolute_position :: proc(widget: UI_Widget) -> (absolute: vec2) {
  ancestor := widget.parent
  x: f32
  y: f32
  for ancestor != nil {
    x += ancestor.position.x
    y += ancestor.position.y

    ancestor = ancestor.parent
  }

  x += widget.position.x
  y += widget.position.y

  return {x, y}
}

// TODO: Size should probably have its own flags
// Fit to text size, fit to parent, fit to children, etc.

make_ui_widget :: proc(flags: bit_set[UI_Widget_Flags], relative_pos: vec2, width, height: f32,
                       text: string) -> (the_widget: ^UI_Widget, results: UI_Results) {
  l, t, b, r: f32
  if .DRAW_TEXT in flags {
    l, t, b, r = text_draw_rect(text, state.default_font, relative_pos.x, relative_pos.y)
  } else {
    l = relative_pos.x
    t = relative_pos.y
    b = t + height
    r = l + width
  }

  // No padding if no text
  TEXT_PADDING :: 5.0
  padding: f32 = TEXT_PADDING if .DRAW_TEXT in flags else 0.0

  w, h: f32
  if .DRAW_BACKGROUND in flags {
    l = l - padding
    t = t - padding
    w = r - l + padding
    h = b - t + padding
  }

  the_widget = array_add(&ui.widgets, UI_Widget {
    flags    = flags,
    position = relative_pos, // Temporarily, will add parent layout info too
    parent   = ui.current_parent,
    width    = w,
    height   = h,
  })

  // Now within the parent's children where does it need to be?
  if ui.current_parent != nil {
    layout_cursor: f32
    for child in array_slice(&ui.current_parent.children) {
      layout_cursor += child.height
      layout_cursor += ui.current_parent.child_padding
    }

    the_widget.position.y += layout_cursor

    array_add(&ui.current_parent.children, the_widget)
  }

  abs := calc_ui_absolute_position(the_widget^)

  // See the results first before we decide how to draw it... might not be good... need to think
  // Also we are calculating
  abs_l := abs.x
  abs_t := abs.y
  abs_b := abs_t + the_widget.height
  abs_r := abs_l + the_widget.width

  if mouse_in_rect(abs_l, abs_t, abs_b, abs_r) {
    results.hovered = true
  }

  if .CLICKABLE in the_widget.flags {
    if results.hovered && mouse_pressed(.LEFT) {
      results.clicked = true
    }
  }

  // FIXME: I have a feeling the way I am recalculating the text position is both not correct
  // and unnecessary

  // TODO: Lots of stuff not configurable right now
  text_height := text_draw_height(text, state.default_font)
  array_add(&ui.draws, UI_Draw {
    text = text,
    text_pos = vec2{abs_l + padding, abs_t + text_height},
    text_color = RED if results.hovered else WHITE,
    quad = {
      top_left = abs,
      width    = w,
      height   = h,
    },
    quad_color = DEFAULT_TEXT_BACKGROUND,
  })

  return the_widget, results
}

ui_push_parent :: proc(widget: ^UI_Widget) {
  ui.current_parent = widget
}

ui_pop_parent :: proc() {
  ui.current_parent = nil
}

ui_panel :: proc(pos: vec2, width, height: f32) -> (panel: ^UI_Widget) {
  panel, _ = make_ui_widget({}, pos, width, height, "")

  return panel
}

// Requires a parent
ui_button :: proc(text: string) -> (results: UI_Results) {
  assert(ui.current_parent != nil)

  _, results = make_ui_widget({.DRAW_TEXT, .DRAW_BACKGROUND, .CLICKABLE}, {}, 0, 0, text)

  return results
}

// Flushes all UI draw records to the immediate rendering system
draw_ui :: proc() {
  immediate_begin(.TRIANGLES, {}, .SCREEN, .ALWAYS)

  for d in array_slice(&ui.draws) {
    immediate_quad(d.quad.top_left, d.quad.width, d.quad.height, d.quad_color)
    draw_text(d.text, state.default_font, d.text_pos.x, d.text_pos.y, d.text_color)
  }

  array_clear(&ui.draws)
  array_clear(&ui.widgets)
}
