# markdown

List editing for markdown buffers in [BeastVim](https://github.com/loctvl842/BeastVim):
Enter continues bullets, numbers and task items (and exits on an empty item), Tab / Shift-Tab
nest and un-nest with numbers kept consecutive, and `o` / `O` continue the list.
Built only for the BeastVim ecosystem - it uses the `Key` and `Treesitter` globals
provided by BeastVim. Not usable standalone.

## Install

```lua
{
  name = "markdown",
  src = gh("BeastVim/markdown"), -- once pushed
  lazy = { filetype = "markdown" },
  config = function() require("markdown").setup() end,
}
```
