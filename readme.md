# love error explorer

by kira

version 0.0.2

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

## version history

version 0.0.2:

- automatically select the right stack frame at start
- don't print full stack contents to terminal by default

version 0.0.1:

- initial release
