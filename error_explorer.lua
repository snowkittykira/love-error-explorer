-- # love error explorer
--
-- by kira
--
-- version 0.0.0 (prerelease)
--
-- an interactive error screen for the love2d game engine.
--
-- on error, shows the stack, local variables, and the
-- source code when available.
--
-- ## usage
--
-- do `require 'error_explorer'` somewhere in your program
-- to set up the error handler.
--
-- when an error happens, press `up` and `down` (or `k` and
-- `j`) to move up and down on the stack. click on tables
-- in the variable view to expand them.

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

-- util ------------------------------------------

local function safe_tostring (value)
  local success, value_string = pcall (tostring, value)
  return success and value_string
                 or ('error during tostring: ' .. value_string)
end

local function shorten (str)
  local result = str:sub(1, 30)
  result = result:match ('^([^\n]*)')
  if #result < #str then
    result = result .. '...'
  end
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
  return from + (to - from) * 0.25
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

local function draw_text (text, x, y)
  local font = love.graphics.getFont ()
  local w = font:getWidth (text)
  local lines = 1
  for _ in text:gmatch ('\n') do
    lines = lines + 1
  end
  local h = font:getHeight () * lines
  love.graphics.print (text, x, y)
  return w, h
end

local function get_stack_info ()
  local stack_info = {}
  local level = 5
  -- maximum 20 stack frames
  while #stack_info < 20 do
    local raw = debug.getinfo (level)
    -- if no more stack frames, stop
    if not raw then break end
    if raw.short_src:sub(1, 1) ~= '[' then
      local info = {
        raw = raw,
        variables = {},
        line = raw.currentline,
        source = raw.short_src,
        fn_name = raw.name or (raw.short_src .. ':' .. tostring (raw.linedefined))
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
  for i = 1, #stack_info do
    local info = stack_info[i]
    print (info.fn_name)
    for j = 1, #info.variables do
      print ('\t' .. tostring (info.variables[j].key) .. ': ' .. shorten (safe_tostring (info.variables[j].value)))
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
	local error_font = love.graphics.setNewFont (16)
	local source_font = love.graphics.newFont (12)
  error_font:setLineHeight (1.25)
  source_font:setLineHeight (1.25)
	love.graphics.setBackgroundColor (1/15, 1/15, 1/15)
	love.graphics.setColor (1, 1, 1, 1)
	love.graphics.clear (love.graphics.getBackgroundColor ())
	love.graphics.origin ()

  -- colors
  local c_dark = {0.5, 0.5, 0.5}
  local c_mid = {0.85, 0.85, 0.85}
  local c_bright = {1, 1, 1}
  local c_red = {1.0, 0.0, 0.0}
  local c_clear = {0.0, 0.0, 0.0, 0.0}
 
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

  -- what location does the error target
  local target_file, target_linenum, msg_without_target = msg:match '^([^:]-%.lua):([^:]-): ?(.*)'
  if target_file then
    target_linenum = tonumber (target_linenum)
    msg = msg_without_target
  end

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
  local source_lines = {}

  local function refresh_source ()
    local frame = stack_info[current_stack_index]
    local filename = frame.source
    if filename then
      source_lines = nil
      pcall (function ()
        source_lines = get_lines (love.filesystem.read(filename))
      end)
    end

  end
  refresh_source ()

  local function keypressed (key)
    if key == 'up' or key == 'k' then
      current_stack_index = math.max (1, current_stack_index - 1)
      refresh_source ()
    end
    if key == 'down' or key == 'j' then
      current_stack_index = math.min (#stack_info, current_stack_index + 1)
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

  local function draw ()
    local W = love.graphics.getWidth ()
    local H = love.graphics.getHeight ()
    local P = 20

    local mx, my = love.mouse.getPosition ()
    local over_section = false
    local x0, y0, x, y

    local function go_to (new_x, new_y)
      x0, y0 = new_x, new_y
      x, y = x0, y0
    end

    local function section (sx, sy, sw, sh)
      over_section =
        mx >= sx and mx < sx + sw and
        my >= sy and my < sy + sh
      love.graphics.setScissor (sx, sy, sw, sh)
      go_to(sx, sy)
    end

    local function print_horizontal (text, color)
      if color then
        love.graphics.setColor (color)
      end
      local dx, dy = draw_text (text, x, y)
      x = x + dx
    end

    local function print_line (text, color)
      if color then
        love.graphics.setColor (color)
      end
      local dx, dy = draw_text (text, x, y)
      x = x0
      y = y + dy
    end
    love.graphics.setFont (error_font)
    local font_height = error_font:getHeight()

    -- error message
    section (P, P, W-2*P, H/2-2*P)
    mouse_over_stack = over_section
    print_line ('error:', c_mid)
    print_line ('  ' .. msg, c_red)

    -- stack frames
    print_line ('stack:', c_mid)
    section (P, y, W-2*P, H/2-2*P-y)
    local stack_top_y = y
    y = y - round (stack_scroll_smooth * font_height)
    local last_hovered_stack_index = hovered_stack_index
    hovered_stack_index = false
    for i, frame in ipairs (stack_info) do
      love.graphics.setColor (last_hovered_stack_index == i and c_bright or
                              current_stack_index == i and c_mid or c_dark)
      local y_before = y
      print_line (string.format ('  %s:%d in function %s',
        frame.source, frame.line, frame.fn_name ))

      if over_section then
        if my >= y_before and my < y then
          hovered_stack_index = i
        end
      end
    end
    stack_max_scroll = #stack_info - (H/2 - stack_top_y) / font_height

    local frame = stack_info [current_stack_index]
    if not frame then
      return
    end

    -- variables
    section (P, H/2, W/2-2*P, H/2-P)
    mouse_over_variables = over_section
    print_line ('variables:', c_mid)
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
      if variable.error then
        print_line ('  ' .. variable.error, c_red)
      else
        print_horizontal (indent .. variable.key, hovered and c_bright or c_mid)
        print_horizontal (': ', variable == last_hovered_variable and c_bright or c_dark)
        print_line (safe_tostring(variable.value))
      end

      if over_section and type (variable.value) == 'table' then
        if mx >= 0 and mx < W/2 and my >= y_before and my < y then
          hovered_variable = variable
        end
      end

      if variable.contents then
        for _, v in ipairs (variable.contents) do
          draw_variable (v, indent .. '  ')
        end
      end
    end
    for _, variable in ipairs (frame.variables) do
      draw_variable (variable, '  ')
    end
    variables_max_scroll = variable_count - (H-P - variables_top_y) / font_height

    -- source
    love.graphics.setFont (source_font)
    local source_height = H/2-P
    section (W/2+P, H/2, W/2-2*P, source_height)
    local line = frame.line
    local lines = math.floor (source_height / source_font:getHeight())
    local context = math.floor ((lines-1) / 2)
    for i = line - context, line + context do
      if source_lines [i] then
        print_horizontal (string.format ('%d', i), i == line and c_mid or c_dark)
        x = x0
        print_horizontal (#source_lines .. '  ', c_clear)
        print_line (source_lines [i], i == line and c_mid or c_dark)
      end
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
      love.timer.sleep (1/60)
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

