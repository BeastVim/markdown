# markdown

List editing for markdown buffers in [BeastVim](https://github.com/loctvl842/BeastVim).
Built only for the BeastVim ecosystem - it uses the `Key` and `Treesitter` globals
provided by BeastVim. Not usable standalone.

| Key | On a list item | Elsewhere |
|---|---|---|
| `<CR>` | Continues the list (same bullet, next number, empty checkbox), splits the item mid-text, un-nests or exits on an empty item | normal Enter |
| `<Tab>` / `<S-Tab>` | Nests / un-nests the item, keeping numbers consecutive on both levels | normal key |
| `o` / `O` | Opens a new item below / above (ordered lists renumber) | normal key |

Bullets (`-`, `*`, `+`), numbers (`1.`, `1)`), task items (`[ ]`, `[x]`) and block quote prefixes
(`> - item`) are recognised. Fenced code blocks are never touched, and the completion menu,
snippet jumps and autopairs keep priority.

`o` / `O` fall back to the plain key on an empty item, in a fence, off a list, and with a count (`3o`).
`.` after `o` / `O` repeats the plain open (a new line without a marker); it never edits the item.

## Install

```lua
{
  name = "markdown",
  src = gh("BeastVim/markdown"), -- once pushed
  lazy = { filetype = "markdown" },
  config = function() require("markdown").setup() end,
}
```
