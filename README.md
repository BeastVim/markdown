# markdown

List editing for markdown buffers in [BeastVim](https://github.com/loctvl842/BeastVim):
Enter continues bullet, numbered and task items, splits an item mid-text, and exits the list
on an empty item. Never active inside fenced code blocks.
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
