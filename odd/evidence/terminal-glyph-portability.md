# Research: terminal width and glyph portability for a zero-dependency CLI

- Retrieved: 2026-10-30T15:12Z (UTC)
- Repository: `darkrei08/setup-ai`, worktree `.worktrees/ui-shell-autonomous`, base commit `94ba2f92106e8ecd3e77b74513b0d798dca8d98b`
- Runtime inspected: Node v22.23.3 (local), Node docs page v26.13.0
- Purpose: resolve wayfinder ticket R1 for the setup-ai launcher/menu graphics change

## Provider and query metadata

| Query / request | Provider | Result |
| --- | --- | --- |
| `exa` URL fetch of `nodejs.org/api/process.html` and `no-color.org` | exa | FAILED: `Missing EXA_API_KEY or exaApiKey in ~/.pi/web-search.json` |
| "Microsoft Windows console legacy host raster font missing Unicode glyph rendering"; "Windows console Unicode support WriteConsoleW code page conhost documentation" | Pi `web_search` (Codex) | 6 sources returned |
| "nodejs.org writeStream.columns ..."; "nodejs tty getColorDepth ... NO_COLOR" with domain filter `nodejs.org` | Pi `web_search` (Codex) | nodejs.org sources returned |
| URL fetch `https://nodejs.org/api/tty.html` | `rich_fetch` (URL mode) | fetched; body truncated at 4000 chars |
| URL fetch `https://no-color.org/` | `rich_fetch` (URL mode) | fetched; body truncated at 2500 chars |
| Local `curl` to no-color.org | bash | BLOCKED by the environment's command guard; not retried |

## Finding 1: terminal width is a runtime property, not a constant

Node documents `writeStream.columns` as "a number specifying the TTY's current number
of columns", updated whenever the `'resize'` event fires.
Source: nodejs.org, "TTY", section `writeStream.columns`
(https://nodejs.org/api/tty.html), retrieved 2026-10-30, provider: Pi `web_search`.

Consequence for setup-ai: `bin/menu.mjs` hardcodes a 70-dash frame while
`createRenderer()` clamps every line to `columns - 1`. At 60 and 72 columns the right
border and corner of the box are therefore dropped (measured pre-change). The frame
must be derived from the live `columns` value, with a floor and a ceiling so that very
narrow and very wide terminals both stay readable.

## Finding 2: encoding success does not imply glyph rendering

`WriteConsoleW` receives UTF-16 and needs no code page, but the console still needs a
font that contains the requested glyph; Microsoft recommends a non-raster (TrueType)
console font such as Consolas or Lucida Console for Unicode output.
Source: Microsoft Learn, `System.Console` (.NET API browser), "Unicode support for the
console" note (https://learn.microsoft.com/dotnet/api/system.console), retrieved
2026-10-30, provider: Pi `web_search`.

A raster console font has limited coverage, and changing the output code page does not
change how extended characters are displayed while a raster font is selected.
Source: Microsoft Learn, `SetConsoleOutputCP`
(https://learn.microsoft.com/windows/console/setconsoleoutputcp), retrieved
2026-10-30, provider: Pi `web_search`.

Legacy Console mode has "especially rudimentary UTF-8 support"; the current console
host is the supported one.
Source: Microsoft Learn, "Legacy Console mode"
(https://learn.microsoft.com/windows/console/legacymode), retrieved 2026-10-30,
provider: Pi `web_search`.

Consequence for setup-ai: `bin/menu.mjs` already detects a console that cannot honour
relative cursor movement (`supportsCursorUp()`) precisely because legacy Windows
consoles are supported. Using `✔` (U+2714) and `➜` (U+279C) in the same frames is
inconsistent with that support level: the bytes arrive, but the glyph may not. ASCII
action marks remove the failure mode without adding a platform branch, and this host
cannot verify a Windows font fix natively, so a capability branch would be unverified.

## Finding 3: colour suppression is a separate, optional contract

The informal NO_COLOR standard says command-line software that adds ANSI colour by
default should suppress colour when `NO_COLOR` is present and not empty.
Source: no-color.org, "NO_COLOR: disabling ANSI color output by default", last updated
2026-10-12 (https://no-color.org/), retrieved 2026-10-30 via `rich_fetch`.

Node's `getColorDepth()`/`hasColors()` treat `NO_COLOR` and `NODE_DISABLE_COLORS` as
colour-disabling inputs, and `TERM=dumb` is documented as making console output avoid
ANSI escapes.
Source: nodejs.org, "TTY", sections `writeStream.getColorDepth`, `writeStream.hasColors`
(https://nodejs.org/api/tty.html), retrieved 2026-10-30, provider: Pi `web_search`.

Consequence for setup-ai: the interactive menu only runs when stdin and stdout are
raw-capable TTYs, and the renderer already refuses relative cursor movement under
`TERM=dumb`. Colour suppression is a real but separate improvement: it is recorded as
out of scope for this bounded change rather than added unrequested.

## Omissions and limits

- The Node page body was truncated by the fetch cap; the quoted `columns` sentence comes
  from the provider summary of that same page, not from a local copy of the HTML.
- No Windows host or Windows-capable container exists on this machine, so Finding 2 is
  documentation evidence only. Nothing here claims a Windows runtime observation.
- `exa` was unavailable for the whole research step; one provider failure is recorded
  above instead of being replaced silently.
