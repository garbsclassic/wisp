# Deliberate choices that look like mistakes

Things a reader — or a review pass — is likely to flag as inconsistent. Each is on purpose;
the reason is here so it doesn't get "fixed" back.

## Auto-surround stays on in raw mode

Raw mode turns off the two smart-editing aids that rewrite a line behind you — `---`→rule and
`:rocket:`→🚀 — but *not* the wrap-the-selection-by-typing-a-delimiter behaviour, which also
rewrites the file. Asked for explicitly: the selection shortcuts are meant to work in raw mode.

The distinction that makes it coherent: the two that go off fire on text you were typing anyway,
turning it into something else. Auto-surround fires only on a selection you deliberately made,
and inserts exactly the character you pressed, twice. It is an edit you asked for by name.

The cost is real and accepted: in raw mode, as everywhere, a selection cannot be replaced by
typing one of `` ` `` `_` `'` `"` `*` `=` `~`. Clear the selection first.

## `faint` is not `tx-3` on light

`Palette.faint` is Flexoki `tx-3` (`#575653`) on dark, but Modernist `ui-2` (`#6A685E`) on light
rather than Modernist's own `tx-3`. Modernist's `tx-3` is `#4B4949`, which is already what
`light.muted` uses — taking it would collapse two tiers into one value and make the tier-ordering
assertion in `ThemeTests` meaningless.

## Escapes touch only the inline passes

`Escapes.Marks.masking` is consulted by `styleInlineMarkup` and `styleHighlights` and by nothing
else, which looks like a gap next to a README that advertises `\#` and `\-`. It isn't: the
structural parsers already refuse those on their own. `\# foo` misses `^(#{1,6})\s+`; `\- foo`
isn't a bullet because `\` is not a bullet character; `1\. foo` isn't ordered because the dot is
not where `listItem` looks; `\---` isn't a rule because the line is not all dashes. What the
escape adds there is only that the backslash is painted as syntax. The inline patterns are the
ones that would otherwise match happily starting one character in.

## `handleTab` inserts at the cursor, `handleBacktab` looks in two places

`⇥` with a bare cursor in prose inserts one indent unit *at the cursor* — that is what a Tab key
is for. `⇧⇥` therefore has two jobs, and tries them in order: take back whitespace immediately
before the caret (`LineEdits.outdentAtCursor`), and failing that outdent the whole block. The
asymmetry in the two functions is what makes the pair symmetric in use.

## Nested list items indent twice

`styleLists` gives a list line `firstLineHeadIndent = width(leading whitespace)` while the
whitespace also renders itself, so a two-space nested item steps in by four spaces' worth. Not an
oversight: two spaces of Inter is eight points, which does not read as a nesting step; doubled it
is about the width of `• `, which is the step Apple Notes uses. `headIndent` and the continuation-
line indent both include the doubling, so wrapped and continuation lines land on the item's text.
