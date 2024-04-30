# love error explorer

by kira

version 0.0.0 (prerelease)

an interactive error screen for the love2d game engine.

on error, shows the stack, local variables, and the
source code when available.

## usage

do `require 'error_explorer'` somewhere in your program
to set up the error handler.

when an error happens, press `up` and `down` (or `k` and
`j`) to move up and down on the stack. click on tables
in the variable view to expand them.
