package main

import "vendor:glfw"

@(private="file")
Menu :: struct {
  title_font: Font,
  item_font:  Font,

  current_item: Menu_Item,
  items:        [Menu_Item]Menu_Item_Info,
}

// NOTE: This might be trying to be too smart
// I mean how many options are really going to have
// Optional confirmations?
@(private="file")
Menu_Item :: enum {
  RESUME,
  RESET,
  QUIT,
}
@(private="file")
Menu_Item_Info :: struct {
  default_message: string,
  confirm_message: string,
  ask_to_confirm:  bool,

  position: vec2,
  size:     vec2,
}

@(private="file")
menu: Menu

init_menu :: proc () -> (ok: bool) {
  menu.title_font, ok = make_font("Diablo_Light.ttf", 90.0)
  menu.item_font, ok  = make_font("Diablo_Light.ttf", 50.0)

  menu.items = {
    .RESUME = {"Resume", "", false, {0, 0}, {0, 0}},
    .RESET  = {"Reset",  "", false, {0, 0}, {0, 0}},
    .QUIT   = {"Quit",   "Confirm Quit?", false, {0, 0}, {0, 0}},
  }

  return ok
}

toggle_menu :: proc() {
  menu.current_item = .RESUME
  switch state.mode {
  case .MENU:
    glfw.SetInputMode(state.window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
    state.mode = .GAME
  case .GAME:
    glfw.SetInputMode(state.window.handle, glfw.CURSOR, glfw.CURSOR_NORMAL)
    state.mode = .MENU
  case .EDIT:
    glfw.SetInputMode(state.window.handle, glfw.CURSOR, glfw.CURSOR_NORMAL)
    state.mode = .MENU
  }
}

update_menu_input :: proc() {
  // Stinks but kind of have to do this to figure out the size
  // once I start work on the generalized ui system... can replace
  x_cursor := f32(state.window.w) * 0.5
  y_cursor := f32(state.window.h) * 0.2
  y_stride := menu.item_font.line_height

  y_cursor += y_stride * 1.7

  advance_item :: proc(step: int) {
    advanced := int(menu.current_item) + step

    if advanced < 0               { advanced = len(Menu_Item) - 1 }
    if advanced >= len(Menu_Item) { advanced = 0 }

    menu.current_item = Menu_Item(advanced)
  }

  if key_repeated(.DOWN) || key_repeated(.S) do advance_item(+1)
  if key_repeated(.UP)   || key_repeated(.W) do advance_item(-1)

  if mouse_scrolled_up()   do advance_item(-1)
  if mouse_scrolled_down() do advance_item(+1)

  for &info, item in menu.items {
    text := info.confirm_message if info.ask_to_confirm else info.default_message

    info.position = {x_cursor, y_cursor}
    info.size.x, info.size.y = text_draw_size(text, menu.item_font)

    if mouse_moved() && mouse_in_rect(text_draw_rect(text, menu.item_font, x_cursor, y_cursor, .CENTER)) {
      menu.current_item = item
    }

    y_cursor += y_stride
  }

  if key_pressed(.ENTER) || mouse_pressed(.LEFT) {
    #partial switch menu.current_item {
    case .RESUME:
      toggle_menu()
    case .RESET:
      state.camera.position = {0,0,0}
      toggle_menu()
    case .QUIT:
      if menu.items[.QUIT].ask_to_confirm == true {
        state.running = false
      } else {
        menu.items[.QUIT].ask_to_confirm = true
      }
    }
  }

  // Reset any items asking for confirmation
  for &info, item in menu.items {
    if item != menu.current_item { info.ask_to_confirm = false }
  }
}

draw_menu :: proc() {
  bind_framebuffer(DEFAULT_FRAMEBUFFER)
  clear_framebuffer(DEFAULT_FRAMEBUFFER, color=LEARN_OPENGL_BLUE)

  x_title := f32(state.window.w) * 0.5
  y_title := f32(state.window.h) * 0.2
  draw_text("Heraclitus", menu.title_font, x_title, y_title, WHITE, .CENTER)

  for info, item in menu.items {
    color := WHITE
    if menu.current_item == item {
      t := f32(cos(seconds_since_start() * 1.4))
      t *= t
      color_1 := LEARN_OPENGL_ORANGE * 0.9
      color_2 := LEARN_OPENGL_ORANGE * 1.1
      color = lerp(color_1, color_2, vec4{t, t, t, 1.0})
    }

    // Check if we should display a confirm message and that the option even has one
    text := info.default_message
    if info.ask_to_confirm && info.confirm_message != "" {
      text = info.confirm_message
      t := f32(cos(seconds_since_start() * 6))
      t *= t
      color = lerp(WHITE, color, vec4{t, t, t, 1.0})
    }

    draw_text(text, menu.item_font, info.position.x, info.position.y,
              color, .CENTER)
  }

  immediate_flush(flush_world=false, flush_screen=true)
}

