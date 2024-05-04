-- # love error explorer
--
-- by kira
--
-- version 0.0.5
--
-- an interactive error screen for the love2d game engine.
--
-- on error, shows the stack, local variables, and the
-- source code when available.
--
-- ## usage
--
-- include `error_explorer.lua` in your project and
-- `require` it somewhere near the start of your program
--
-- when an error happens, press `up` and `down` (or `k` and
-- `j`) to move up and down on the stack, click on tables
-- in the variable view to expand them, and scroll with the
-- mousewheel.
--
-- you can provide an optional table when requiring error
-- explorer to provide options:
--
-- ```lua
-- require 'error_explorer' {
--   -- change the limit of stack depth (default 20)
--   stack_limit = 20,
--
--   -- provide custom font for error / stack trace / variables
--   error_font = love.graphics.newFont (16),
--
--   -- provide custom font for source code
--   source_font = love.graphics.newFont (12),
--
--   -- provide `open_editor` to run a command when
--   -- clicking a source line (disabled in fused builds,
--   -- and when running from a file ending in .love, but
--   -- it's safer to remove this when distributing)
--   open_editor = function (filename, line)
--     -- for example using neovim remote
--     io.popen ('nvr ' .. filename .. ' +' .. line)
--   end,
-- }
-- ```
--
-- ## version history
--
-- version 0.0.5:
--
-- - added options table for configuring:
--   - stack limit
--   - fonts
--   - optional "open in editor" action
-- - use less cpu when idle
--
-- version 0.0.4:
--
-- - fix for non-string keys and multiline keys
--
-- version 0.0.3:
--
-- - handle when source file isn't available
--
-- version 0.0.2:
--
-- - automatically select the right stack frame at start
-- - don't print full stack contents to terminal by default
--
-- version 0.0.1:
--
-- - initial release

-- ## license
--
-- Copyright 2024 Kira Boom
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the “Software”), to
-- deal in the Software without restriction, including without limitation the
-- rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
-- sell copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS
-- OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

local utf8 = require("utf8")

local print_stack_variables_to_terminal = false
local stack_limit = 20
local open_editor
local error_font
local source_font

-- util ------------------------------------------

local function is_build ()
  return love.filesystem.isFused () or
    love.filesystem.getSource ():match ('%.love$')
end

local function safe_tostring (value)
  local success, value_string = pcall (tostring, value)
  return success and value_string
                 or ('error during tostring: ' .. value_string)
end

local function shorten (str)
  local result = str:sub(1, 30)
  if #result < #str then
    result = result .. '...'
  end
  result = result:gsub ('\n', ' ')
  return result
end

local function compare_keys (a, b)
  local ta = type (a.key)
  local tb = type (b.key)
  if ta ~= tb then
    return ta < tb
  end
  if ta == 'number' or ta == 'string' then
    return a.key < b.key
  else
    return safe_tostring (a.key) < safe_tostring (b.key)
  end
end

local function approach (from, to)
  local value = from + (to - from) * 0.25
  if math.abs (value - to) * source_font:getHeight() < 0.5 then
    value = to
  end
  return value
end

local function round (n)
  return math.floor (n + 0.5)
end

local function get_lines (text)
  local lines = {}
  for line in text:gmatch ("(.-)\r?\n") do
    table.insert (lines, line)
  end
  local last_line = text:match ('([^\n]*)$')
  if last_line and last_line ~= '' then
    table.insert (lines, last_line)
  end
  return lines
end

local function get_font_height ()
  local font = love.graphics.getFont ()
  return math.ceil (font:getHeight () * font:getLineHeight ())
end

local function draw_text (text, x, y)
  text = text or ''
  local font = love.graphics.getFont ()
  local w = font:getWidth (text)
  local lines = 1
  for _ in text:gmatch ('\n') do
    lines = lines + 1
  end
  local h = get_font_height () * lines
  love.graphics.print (text, x, y)
  return w, h
end

local function get_stack_info ()
  local stack_info = {}
  local level = 5
  -- maximum stack frames
  while #stack_info < stack_limit do
    local raw = debug.getinfo (level)
    -- if no more stack frames, stop
    if not raw then break end
    if raw.short_src:sub(1, 1) ~= '[' then
      local info = {
        raw = raw,
        variables = {},
        line = raw.currentline,
        source = raw.short_src,
        fn_name = raw.name or raw.linedefined ~= 0 and (raw.short_src .. ':' .. tostring (raw.linedefined))
      }
      table.insert (stack_info, info)

      -- local variables
      local local_index = 1
      repeat
        local name, value = debug.getlocal (level, local_index)
        if name then
          if name ~= '(*temporary)' then
            table.insert (info.variables, {
              key = name,
              value = value
            })
          end
          local_index = local_index + 1
        end
      until not name

      -- upvalues and env
      --info.upvalues = {}
      if raw.func then
        local upvalue_index = 1
        repeat
          local name, value = debug.getupvalue (raw.func, upvalue_index)
          if name then
            table.insert (info.variables, {
              key = name,
              value = value,
            })
            upvalue_index = upvalue_index + 1
          end
        until not name

        if rawget (_G, 'getfenv') then
          local env = getfenv (raw.func)
          table.insert (info.variables, { key = '_ENV', value = env })
        end
      end

    end
    level = level + 1
  end
  return stack_info
end

-- handle error ----------------------------------

local function handle_error (msg)
	msg = tostring (msg)

  -- print error
	print (debug.traceback ("Error: " .. msg, 5))

  local stack_info = get_stack_info ()
  if print_stack_variables_to_terminal then
    for i = 1, #stack_info do
      local info = stack_info[i]
      print (string.format ('%s:%d', info.source, info.line) ..
        (info.fn_name and (' in function ' .. info.fn_name) or ' at top level'))
      for j = 1, #info.variables do
        print ('\t' .. tostring (info.variables[j].key) .. ': ' .. shorten (safe_tostring (info.variables[j].value)))
      end
    end
  end

  -- do nothing if modules not available
	if not love.window or not love.graphics or not love.event then
		return
	end

  -- open a window if needed
	if not love.graphics.isCreated () or not love.window.isOpen () then
		local success, status = pcall (love.window.setMode, 800, 600)
		if not success or not status then
			return
		end
	end

	-- reset mouse
	if love.mouse then
		love.mouse.setVisible (true)
		love.mouse.setGrabbed (false)
		love.mouse.setRelativeMode (false)
		if love.mouse.isCursorSupported() then
			love.mouse.setCursor()
		end
	end

  -- reset joystick vibration
	if love.joystick then
		for i, v in ipairs (love.joystick.getJoysticks ()) do
			v:setVibration ()
		end
	end

  -- stop audio
	if love.audio then
    love.audio.stop ()
  end

  -- reset graphics
	love.graphics.reset ()
  if not error_font then
    error_font = love.graphics.newFont (16)
    error_font:setLineHeight (1.2)
  end
  if not source_font then
    source_font = love.graphics.newFont (12)
    source_font:setLineHeight (1.2)
  end
	love.graphics.setBackgroundColor (1/15, 1/15, 1/15)
	love.graphics.setColor (1, 1, 1, 1)
	love.graphics.clear (love.graphics.getBackgroundColor ())
	love.graphics.origin ()

  -- colors
  local c_verydark = {0.25, 0.25, 0.25}
  local c_dark     = {0.5, 0.5, 0.5}
  local c_mid      = {0.7, 0.7, 0.7}
  local c_bright   = {1.0, 1.0, 1.0}
  local c_red      = {1.0, 0.0, 0.0}
  local c_clear    = {0.0, 0.0, 0.0, 0.0}
 
  -- sanitize utf-8
	local sanitizedmsg = {}
	for char in msg:gmatch(utf8.charpattern) do
		table.insert(sanitizedmsg, char)
	end
	sanitizedmsg = table.concat(sanitizedmsg)
  local invalid_utf8 = sanitizedmsg ~= msg
  msg = sanitizedmsg

  -- get the backtrace
	local trace = debug.traceback ('', 4)

  -- start error explorer

  -- stack view
  local current_stack_index = 1
  local hovered_stack_index = false
  local mouse_over_stack = false
  local stack_max_scroll = 0
  local stack_scroll = 0
  local stack_scroll_smooth = 0

  -- variables view
  local hovered_variable = false
  local variables_max_scroll = 0
  local variables_scroll = 0
  local variables_scroll_smooth = 0
  local mouse_over_variables = false

  -- source view
  local hovered_source_line

  -- idle tracking
  local mouse_moved_time = 0

  -- what location does the error target
  local target_file, target_linenum, msg_without_target = msg:match '^([^:]-%.lua):([^:]-): ?(.*)'
  if target_file then
    target_linenum = tonumber (target_linenum)
    msg = msg_without_target
    for i = 1, #stack_info do
      if target_file == stack_info[i].source and target_linenum == stack_info[i].line then
        current_stack_index = i
        break
      end
    end
  end

  -- source view
  local source_lines

  local function refresh_source ()
    source_lines = nil
    local frame = stack_info[current_stack_index]
    local filename = frame.source
    if filename then
      pcall (function ()
        source_lines = get_lines (love.filesystem.read(filename))
      end)
    end

  end
  refresh_source ()

  local function keypressed (key)
    if key == 'up' or key == 'k' then
      current_stack_index = math.max (1, current_stack_index - 1)
      stack_scroll = math.min (current_stack_index-1, stack_scroll)
      refresh_source ()
    end
    if key == 'down' or key == 'j' then
      current_stack_index = math.min (#stack_info, current_stack_index + 1)
      stack_scroll = math.max (current_stack_index - (#stack_info - stack_max_scroll), stack_scroll)
      refresh_source ()
    end
  end

  local function mousepressed ()
    if hovered_stack_index then
      current_stack_index = hovered_stack_index
      refresh_source ()
    end
    if hovered_variable and type (hovered_variable.value) == 'table' then
      if hovered_variable.contents then
        hovered_variable.contents = nil
      else
        local contents = {}
        hovered_variable.contents = contents
        for k,v in pairs (hovered_variable.value) do
          table.insert (contents, {
            key = k,
            value = v,
          })
        end
        table.sort (contents, compare_keys)
      end
    end
    if hovered_source_line then
      local frame = stack_info[current_stack_index]
      if frame then
        open_editor (frame.source, hovered_source_line)
      end
    end
  end

  local function wheelmoved (amount)
    if mouse_over_stack then
      stack_scroll = math.max (0, math.min (stack_scroll - amount * 2, stack_max_scroll))
    end
    if mouse_over_variables then
      variables_scroll = math.max (0, math.min (variables_scroll - amount * 2, variables_max_scroll))
    end
  end

  local function update ()
    stack_scroll_smooth = approach (stack_scroll_smooth, stack_scroll)
    variables_scroll_smooth = approach (variables_scroll_smooth, variables_scroll)
  end

  local function is_idle ()
    if love.timer then
      if love.timer.getTime() < mouse_moved_time + 1 then
        return false
      end
    end
    return stack_scroll_smooth == stack_scroll and
           variables_scroll_smooth == variables_scroll
  end

  local function draw ()
    local W = love.graphics.getWidth ()
    local H = love.graphics.getHeight ()
    local P = 50

    local mx, my = love.mouse.getPosition ()
    local over_section = false
    local sx, sy, sw, sh
    local x, y

    local function section (new_sx, new_sy, new_sw, new_sh)
      sx, sy = new_sx, new_sy
      sw, sh = new_sw, new_sh
      x, y = sx, sy
      over_section =
        mx >= sx and mx < sx + sw and
        my >= sy and my < sy + sh
      love.graphics.setScissor (sx, sy, sw, sh)
    end

    local function print_horizontal (text, color)
      if color then
        love.graphics.setColor (color)
      end
      local dx, _dy = draw_text (text, x, y)
      x = x + dx
    end

    local function print_line (text, color)
      if color then
        love.graphics.setColor (color)
      end
      local _dx, dy = draw_text (text, x, y)
      x = sx
      y = y + dy
    end

    local function draw_scrollbar (scroll, scroll_height, visible_height)
      if scroll_height <= visible_height then
        return
      end
      love.graphics.setColor (c_verydark)
      love.graphics.rectangle ('fill', sx + sw - 2, sy, 2, sh, 2, 2, 2)
      local scroll_y = scroll / scroll_height
      local scroll_h = visible_height / scroll_height
      love.graphics.setColor (c_dark)
      love.graphics.rectangle ('fill', sx + sw - 2, sy + scroll_y * sh, 2, scroll_h*sh, 2, 2, 2)
    end

    love.graphics.setFont (error_font)
    local font_height = get_font_height ()

    -- error message
    section (P, P, W/2-2*P, H-2*P)
    print_line ('error explorer', c_dark)
    local _, wrapped_error = error_font:getWrap (msg, W/2-2*P)
    for _, text in ipairs (wrapped_error) do
      print_line (text, c_bright)
    end
    print_line ()
    local left_space_left = H-P - y
    local left_section_height = math.floor ((left_space_left - font_height)/2)

    -- stack frames
    --print_line ('stack', c_dark)
    section (P, y, W/2-2*P, left_section_height)
    mouse_over_stack = over_section
    local stack_top_y = y
    y = y - round (stack_scroll_smooth * font_height)
    local last_hovered_stack_index = hovered_stack_index
    hovered_stack_index = false
    for i, frame in ipairs (stack_info) do
      local light_color = c_mid
      local dark_color = c_dark
      if last_hovered_stack_index == i or current_stack_index == i then
        light_color = c_bright
        dark_color = c_bright
      end
      local y_before = y
      print_horizontal (string.format ('%s:%d', frame.source, frame.line), light_color)
      if frame.fn_name then
        print_horizontal (' in function ', dark_color)
        print_horizontal (string.format ('%s', frame.fn_name), light_color)
      else
        print_horizontal (' at top level', dark_color)
      end
      print_line ()

      if over_section then
        if my >= y_before and my < y then
          hovered_stack_index = i
        end
      end
    end
    local stack_lines_shown = (sy + left_section_height - stack_top_y) / font_height
    stack_max_scroll = #stack_info - stack_lines_shown
    draw_scrollbar (stack_scroll_smooth, #stack_info, stack_lines_shown)

    local frame = stack_info [current_stack_index]
    if not frame then
      return
    end

    -- variables
    section (P, sy+left_section_height+font_height, W/2-2*P, left_section_height)
    mouse_over_variables = over_section
    --print_line ('variables', c_dark)
    section (P, y, W/2 - 2*P, H-P-y)
    local variables_top_y = y
    y = y - round (variables_scroll_smooth * font_height)
    local last_hovered_variable = hovered_variable
    hovered_variable = false
    local variable_count = 0
    local function draw_variable (variable, indent)
      variable_count = variable_count + 1
      local hovered = variable == last_hovered_variable
      local y_before = y
      print_horizontal (indent .. shorten(safe_tostring (variable.key)), hovered and c_bright or c_mid)
      print_horizontal (': ', variable == last_hovered_variable and c_bright or c_dark)
      print_line (safe_tostring(variable.value))

      if over_section and type (variable.value) == 'table' then
        if mx >= 0 and mx < W/2 and my >= y_before and my < y then
          hovered_variable = variable
        end
      end

      if variable.contents then
        for _, v in ipairs (variable.contents) do
          draw_variable (v, indent .. '\t')
        end
      end
    end
    for _, variable in ipairs (frame.variables) do
      draw_variable (variable, '')
    end
    local variables_lines_shown = (H-P - variables_top_y) / font_height
    variables_max_scroll = variable_count - variables_lines_shown
    draw_scrollbar (variables_scroll_smooth, variable_count, variables_lines_shown)

    -- source
    love.graphics.setFont (source_font)
    section (W/2+P, P, W/2-2*P, H-2*P)
    print_line (frame.source .. '\n', c_dark)
    local prev_hovered_line = hovered_source_line
    hovered_source_line = nil
    if source_lines then
      local source_height = H-P - y
      local line = frame.line
      local lines = math.floor (source_height / get_font_height ())
      local context = math.floor ((lines-1) / 2)
      for i = line - context, line + context do
        if source_lines [i] then
          local y_before = y
          local hovered = i == prev_hovered_line
          local color = (hovered or i == line) and c_bright or c_dark
          print_horizontal (string.format ('%d', i), color)
          x = sx
          print_horizontal (#source_lines .. '    ', c_clear)
          print_line (source_lines [i], color)
          if open_editor and over_section and y_before <= my and my < y then
            hovered_source_line = i
          end
        end
      end
    else
      print_line ('source unavailable')
    end
  end

  -- main loop
	return function ()
    -- handle events
    love.event.pump ()
    for e, a, b, c in love.event.poll () do
      if e == "quit" or e == "keypressed" and a == "escape" then
        return 1
      elseif e == "keypressed" then
        keypressed (a)
      elseif e == "mousepressed" and c == 1 then
        mousepressed ()
      elseif e == "mousemoved" and love.timer then
        mouse_moved_time = love.timer.getTime ()
      elseif e == "wheelmoved" and b ~= 0 then
        wheelmoved (b)
      elseif e == "touchpressed" then
        local name = love.window.getTitle ()
        if #name == 0 or name == "Untitled" then
          name = "Game"
        end
        local pressed = love.window.showMessageBox (
          "Quit " .. name .. "?", "", {"OK", "Cancel"})
        if pressed == 1 then
          return
        end
      end
    end

    update ()

    -- draw
    love.graphics.clear (love.graphics.getBackgroundColor ())
    draw ()
    love.graphics.setScissor()
    love.graphics.present ()

    -- wait
    if love.timer then
      if is_idle () then
        love.timer.sleep (1/20)
      else
        love.timer.sleep (1/60)
      end
    end
	end
end

local errhand = love.errhand

function love.errhand (msg)
  local success, result = pcall (handle_error, msg)
  if not success then
    return errhand (tostring (msg) .. '\n\nerror during error handling: ' .. tostring (result))
  end

  local loop = result
  local failed = false

  return function ()
    if failed then
      return loop ()
    else
      success, result = pcall (loop)
      if not success then
        failed = true
        loop = errhand (tostring (msg) .. '\n\nerror during error handling: ' .. tostring (result))
        return loop ()
      end
      return result
    end
  end
end

return function (options)
  if options.stack_limit then
    if type (options.stack_limit) ~= 'number' then
      error ('when provided, stack_limit must be a number')
    end
    stack_limit = math.floor (options.stack_limit)
  end
  if options.open_editor and not is_build () then
    if type (options.open_editor) ~= 'function' then
      error ('when provided, `open_editor` should be a function', 2)
    end
    open_editor = options.open_editor
  end
  if options.error_font then
    if type(options.error_font) ~= 'userdata' or not options.error_font:typeOf 'Font' then
      error('when provided, error_font must be a font', 2)
    end
    error_font = options.error_font
  end
  if options.source_font then
    if type(options.source_font) ~= 'userdata' or not options.source_font:typeOf 'Font' then
      error('when provided, source_font must be a font', 2)
    end
    source_font = options.source_font
  end
end
