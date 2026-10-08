# Keys

Every key omawsl sets up, plus the ones worth knowing in the tools it installs. In a
terminal: `omawsl keys` shows all of it, `omawsl keys <section>` just one - e.g.
`omawsl keys herdr`, `omawsl keys nvim`, `omawsl keys lazygit`.

For the tools omawsl only installs (Neovim, lazygit, lazydocker, btop), these are the
essentials, not every key - each section ends with how to open that tool's full list.

## zellij / Herdr

omawsl gives zellij and Herdr the same keymap, so this works in whichever one your
terminals open (`omawsl multiplexer`). Typing goes to the pane until you press `Ctrl g`.

| You press | Does |
|---|---|
| `Alt h/j/k/l`, `Alt ←/↓/↑/→` | focus the pane that way (`h`/`l` switch tab at the edge) |
| `Alt n` | new pane |
| `Alt =` / `Alt -` | grow / shrink the pane |
| `Alt i` / `Alt o` | move the tab left / right |
| `Alt f` | zellij: floating panes - Herdr: a scratch shell popup (exit it to get back) |
| `Ctrl g p` | pane mode - `hjkl` focus, `n` new, `d` split down, `r` split right, `x` close, `f` fullscreen, `c` rename, `Tab` next |
| `Ctrl g t` | tab mode - `hjkl` switch, `1-9` go to, `n` new, `x` close, `r` rename, `b` break pane out, `[` `]` break pane left / right |
| `Ctrl g r` | resize mode - `hjkl` move the border that way, `HJKL` shrink, `+` `-` grow / shrink |
| `Ctrl g m` | move mode - `hjkl` swap with the pane that way, `n`/`Tab` next, `p` previous |
| `Ctrl g s` | scroll - `j/k`, `PageUp/PageDown`, `Ctrl b/Ctrl f`; half page `u/d` in zellij, `Ctrl u/Ctrl d` in Herdr |
| `Ctrl g o` | session mode - zellij: `d` detach, `w` sessions |
| `Ctrl g Ctrl q` | quit |
| `Esc`, `Enter`, `Ctrl g` | leave a mode |

### Herdr only

| You press | Does |
|---|---|
| `Ctrl g g` | jump to any agent or terminal - `j/k` move, `Enter` go, `/` search, `b/w/i/d` only blocked / working / idle / done, `a` all |
| `Ctrl g w` | workspace picker |
| `Ctrl g [/]` | previous / next workspace |
| `Ctrl g 1-9` | workspace 1-9 (tabs are `Ctrl g t 1-9`) |
| `Ctrl g b` | show / hide the sidebar of agents |
| `Ctrl g q` | detach - everything keeps running |
| `Ctrl g e` | open the pane's scrollback in your editor |
| `Ctrl g ,` | Herdr settings |
| `Ctrl g ?` | Herdr's own key help |

### zellij only

| You press | Does |
|---|---|
| `Alt [` / `Alt ]` | previous / next swap layout |
| `Alt +` | grow the pane (same as `Alt =`) |
| `Ctrl g s`, then `f` | search the scrollback - `n` / `p` next / previous |

## Shell

| You press | Does |
|---|---|
| `Ctrl r` | search command history (fzf) |
| `Ctrl t` | pick a file and paste its path (fzf) |
| `Alt c` | pick a folder and `cd` into it (fzf) |
| `↑` / `↓` | previous / next command starting with what you've typed |
| `Tab` | complete - case doesn't matter, all matches show at once |

Handy commands:

| Type | Does |
|---|---|
| `z <part of a path>` (or `cd`) | jump to a folder you've been in before |
| `..`, `...`, `....` | up one, two, three folders |
| `ll`, `lsa`, `lt` | list files - long, with hidden, as a tree |
| `ff` | find a file with a preview |
| `n` | Neovim in this folder (`n file` opens a file) |
| `g`, `gcm "msg"`, `gcam "msg"`, `gcad` | git, commit, commit all, amend all |
| `lzg`, `lzd` | lazygit, lazydocker |
| `d` | docker |
| `omawsl keys` | this cheatsheet |

## Claude Code

| You press | Does |
|---|---|
| `Esc` | stop Claude mid-answer |
| `Esc Esc` | go back to an earlier message |
| `Shift Tab` | switch mode (normal / auto-accept edits / plan) |
| `@` | mention a file |
| `/` | slash commands |
| `!` | run a shell command |
| `PgUp` / `PgDn` | scroll the chat |
| `Ctrl End` | back to the latest message |
| `Ctrl o` | transcript - `j/k` line by line, `{ }` between your prompts, `/` search, `Esc` back |
| `↑` | prompt history |

Claude Code draws its own screen, so zellij / Herdr scroll mode doesn't reach the chat - use
the keys above. Full list: `?` on an empty prompt.

## Neovim (nvim)

omawsl installs LazyVim's defaults. `Space` is the leader key: press it and wait for a menu
of everything that follows it.

| You press | Does |
|---|---|
| `Space Space` | find a file |
| `Space /` | search text in the project |
| `Space f r` | recent files |
| `Space ,` | open files (buffers) |
| `Space e` | file explorer |
| `Shift h` / `Shift l` | previous / next open file |
| `Space b d` | close the file |
| `Ctrl h/j/k/l` | move between splits |
| `Space -` / `Space \|` | split below / right |
| `gd` / `gr` | go to definition / references |
| `K` | docs for what's under the cursor |
| `Space c a` / `Space c r` / `Space c f` | code action / rename / format |
| `gcc` | comment the line |
| `s` | jump anywhere on screen (type the label it shows) |
| `Space g g` | lazygit |
| `Ctrl /` | terminal |
| `Space x x` | errors and warnings |
| `Ctrl s` | save |
| `Space q q` | quit |
| `Space l` | plugin manager |

Full list: `Space s k` searches every key.

## lazygit

Open with `lzg` (or `Space g g` in Neovim).

| You press | Does |
|---|---|
| `h/l`, `←/→`, `Tab` | switch panel |
| `1-5` | jump to status / files / branches / commits / stash |
| `j/k`, `↑/↓` | move in a list |
| `Space` | files: stage / unstage - branches: check out |
| `a` | stage all |
| `Enter` | files: stage single lines - elsewhere: open |
| `c` | commit |
| `A` | amend the last commit |
| `d` | discard / delete |
| `p` / `P` | pull / push |
| `n` | branches: new branch |
| `M` / `r` | branches: merge into current / rebase current onto it |
| `s` / `f` / `r` | commits: squash / fixup / reword |
| `z` | undo |
| `/` | search |
| `+` | bigger view |
| `q` | quit |

Full list: `?`.

## lazydocker

Open with `lzd`.

| You press | Does |
|---|---|
| `1-6` | projects / services / containers / images / volumes / networks |
| `j/k`, `↑/↓` | move in a list |
| `Enter` / `Esc` | into / out of the right-hand panel |
| `[` / `]` | switch tab there - logs, stats, env, config, top |
| `s` / `r` / `d` | stop / restart / remove |
| `E` | open a shell inside the container |
| `a` | attach |
| `m` | logs |
| `w` | open in the browser |
| `e` | show / hide stopped containers |
| `u` / `U` / `D` | services: up / up project / down project |
| `/` | filter |
| `+` | bigger view |
| `q` | quit |

Full list: `x` or `?`.

## btop

| You press | Does |
|---|---|
| `↑/↓` | pick a process |
| `Enter` | details of that process |
| `f` or `/` | filter processes |
| `←/→` | sort by another column |
| `r` | reverse the sort |
| `e` | tree view |
| `t` / `k` | terminate / kill the process |
| `1-5` | show / hide CPU / memory / network / processes / GPU |
| `m` or `Esc` | menu |
| `o` | options |
| `q` | quit |

Full list: `?`.
