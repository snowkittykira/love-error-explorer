# love error explorer

by kira

version 0.0.5

an interactive error screen for the love2d game engine.

on error, shows the stack, local variables, and the
source code when available.

## usage

include `error_explorer.lua` in your project and
`require` it somewhere near the start of your program

when an error happens, press `up` and `down` (or `k` and
`j`) to move up and down on the stack, click on tables
in the variable view to expand them, and scroll with the
mousewheel.

you can provide an optional table when requiring error
explorer to provide options:

```lua
require 'error_explorer' {
  -- change the limit of stack depth (default 20)
  stack_limit = 20,

  -- provide custom font for error / stack trace / variables
  error_font = love.graphics.newFont (16),

  -- provide custom font for source code
  source_font = love.graphics.newFont (12),

  -- provide `open_editor` to run a command when
  -- clicking a source line (disabled in fused builds,
  -- and when running from a file ending in .love, but
  -- it's safer to remove this when distributing)
  open_editor = function (filename, line)
    -- for example using neovim remote
    io.popen ('nvr ' .. filename .. ' +' .. line)
  end,
}
```

## version history

version 0.0.5:

- added options table for configuring:
  - stack limit
  - fonts
  - optional "open in editor" action
- use less cpu when idle

version 0.0.4:

- fix for non-string keys and multiline keys

version 0.0.3:

- handle when source file isn't available

version 0.0.2:

- automatically select the right stack frame at start
- don't print full stack contents to terminal by default

version 0.0.1:

- initial release
