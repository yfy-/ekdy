# ekdy

A fast, character-level HTML-to-text library in Zig. Single pass, no
DOM, no token stream.

ekdy is an event-based HTML parser designed for high-throughput text
extraction: crawlers, search engines, and LLM data pipelines. It
processes input character by character in a single pass, emitting text
directly without building any intermediate representation.

Output fidelity is validated against the
[html5lib-tests](https://github.com/html5lib/html5lib-tests) corpus
using Chromium's `innerText` as the oracle. Nearly all cases match
exactly, with small differences mostly due to adoption rules — an
inherent property of a non-rendering, single-pass design. See [Known
limitations](#known-limitations).

## Benchmarks

ekdy outperforms other established html2text programs.
Results on Apple (M5 Max 18 cores) and Intel (i5-12400F) processors:

| Platform | Html2Text Program | MB/s |
|----------|-------------------|----- |
| Apple | ekdy | 628 |
| Apple | resiliparse (Lexbor) |406 |
| Apple | html2text (html5ever) | 138 |
| Intel | ekdy | 452 |
| Intel | resiliparse (Lexbor) | 116 |
| Intel | html2text (html5ever) | 77 |

Tested on a Web Archive of 19786 HTML documents with a total size of
3.5GB.

Full methodology and reproducible benchmark suite: [html2text-bench](https://codeberg.org/yfy/html2text-bench).

## Design

ekdy is fast because it refuses to build anything it doesn't need.
There is no DOM, no token stream, and minimal allocation between input
and output: a single character-level state machine walks the input
once and emits text as it goes.

Extraction behavior is a comptime policy. The built-in `InnerText`
policy mimics Chromium's `innerText` semantics (block/inline tags,
whitespace collapsing); custom policies can be supplied at compile
time with zero runtime dispatch cost.

## Building

Requires Zig 0.16.

```sh
zig build -Doptimize=ReleaseFast
```

## Usage

### CLI

```sh
curl -sL https://example.com | zig-out/bin/ekdy
```

### As a library

```zig
const std = @import("std");
const ekdy = @import("ekdy");
const InnerText = ekdy.policy.InnerText;

var allocating = std.Io.Writer.Allocating.init(allocator);
defer allocating.deinit();

var policy = InnerText{};
var extractor = try ekdy.html.TextExtractor(InnerText).init(allocator, &allocating.writer, &policy);
defer extractor.deinit(allocator);

try extractor.convertAll(allocator, html);
const text = allocating.written();
```

The current API processes complete documents. Streaming (chunked)
input is on the roadmap; see below.

## Test suite

ekdy's correctness tests are generated from the html5lib-tests corpus,
with expected outputs produced by Chromium's `innerText`. Regenerating
the test cases is optional and Linux-only. It requires:

- Python (with the `websocket-client` package)
- Chromium
- GNU `parallel`

Test cases can be regenerated with:

```sh
scripts/gen_all_tests.sh
```

All tests can be executed with:

```sh
zig test src/decoding.zig
zig test src/html.zig
```

## Roadmap

- Streaming parsing (chunked input).
- C ABI (`libekdy`) and Python bindings.
- More complete parser events such as attributes.
- Markdown text output policy.
- SIMD optimizations: Vectorized scanning for tag boundaries and
  entity detection in hot paths.

## Known limitations

### Adoption Rules
For the following html:

```html
<DIV> abc <B> def <I> ghi <P> jkl </B> mno </I> pqr </P> stu
```

ekdy outputs:

```
abc def ghi

jkl mno pqr stu
```

chromium inner text outputs:

```
abc def ghi

jkl mno pqr

stu
```

`stu` is printed on a new line since adoption rules of a DOM based
parser can fix the malformed HTML, whereas for ekdy after `</B>` the
paragraph also ends and the following `</P>` does not cause another
block level whitespace to be outputted that prints the `stu` on a new
line.

### Table Foster Parenting

For the following html:

```html
<a href="blah">aba<table><tr><td><a href="foo">br</td></tr>x</table>aoe
```

ekdy outputs:

```
aba
brx
aoe
```

chromium inner text outputs:

```
abax
br
aoe
```

In a `<table>` only valid text can appear within special tags such as
`<tr>`/`<td>`, any other text is pushed outside the `<table>`'s parent
tag. Therefore a DOM based parser can push the character `x` after
`aba` whereas ekdy outputs `x` as soon as it encounters it.

### Other cases

ekdy can also output slightly different text in `<select>`, `<svg>`,
`<template>`, `<details>` and `<dialog>` tags.
