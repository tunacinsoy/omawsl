# Fonts

This directory intentionally contains no font binaries — see `docs/windows-setup.md#fonts`
for the two documented options.

If you want the Nerd Font (enhanced) option, download it directly from the same upstream
release Omakub's own font installer uses:

https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip

Unzip it and install every `.ttf` inside (right-click → Install, no admin rights needed in
the common case). The font family name after installing is **`CaskaydiaMono Nerd Font Mono`**
(not `Cascadia Mono` — Nerd Fonts renames patched fonts to avoid a font-license naming
conflict), which is exactly what `../windows-terminal.json` sets as the profile's font face.

If you'd rather not install anything, use the zero-install fallback instead: merge
`../windows-terminal-fallback.json`, which points at `Cascadia Mono`, the font Windows
Terminal already ships with. See `docs/windows-setup.md#fonts` for the full comparison.
