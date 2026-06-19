---
name: typst
description: Generate beautiful printable PDF documents from natural language, markdown, or arbitrary text content using Typst. Triggers include requests to "write a document", "create a PDF", "make a printable version", "export to PDF", "format this as a document", or any mention of creating a shareable/printable document.
---

# Typst: intelligent document generation

This skill produces polished, print-ready PDFs. Don't just pass content through. Analyze what kind of document it is and make intentional choices about style, structure, and metadata before compiling.

The compiler is `~/bin/typst-doc`. Output goes to `~/Desktop/<stem>.pdf` by default (overwrites any existing file of the same name; no suffixes).

---

## Style selection (most important decision)

```
--style warm          personal, spiritual, relational, recovery docs, letters
--style professional  business reports, proposals, meeting notes, memos
--style minimal       clean modern notes, technical docs
--style academic      research papers, theses, citations-heavy writing
--style creative      portfolios, creative writing, personal brand
```

**Warm** = Crimson Pro font, amber/brown headings, left-aligned, no running header. Reads like a human document, not a legal contract. Use it for anything personal or intimate.

**Professional** = New Computer Modern, navy headings, justified, running header. Classic and polished.

**Minimal** = understated grays, tight sizing. Clean and modern.

Map user's natural language hints to style:
"clean / modern / simple" becomes minimal
"personal / warm / friendly" becomes warm
"formal / corporate / official" becomes professional
"paper / research / academic" becomes academic
"creative / expressive / portfolio" becomes creative

---

## Pre-compile checklist

Before calling `typst-doc`, always:

1. **Extract the title** from the content if not provided. Don't let it remain as the first `# Heading` in the body AND also be passed as `--title`. The script deduplicates, but you should be deliberate.

2. **Drop redundant headings** - if the first heading in the body matches the `--title` (same or very similar), either omit `--title` or omit the heading, not both. The script will auto-drop the heading if it detects a match, but be explicit.

3. **Fix bold-as-labels** - `**term** rest of sentence` in bullet lists is a "term: description" pattern. Ensure the style allows it to render as bold (warm style does; all styles do with the fixed converter).

4. **No preamble explaining what the document is** - cut meta-commentary ("This document outlines..."). Let the title and structure speak.

---

## Compiling

```bash
# Content via stdin (most common):
printf '%s' "<markdown>" | ~/bin/typst-doc \
  --style warm \
  --title "Recovery Agreement" \
  --author "Patrick Taylor" \
  --date "June 2026"

# From a file:
~/bin/typst-doc ~/path/to/file.md --style professional --title "Q2 Report"

# Suppress auto-open:
printf '%s' "<content>" | ~/bin/typst-doc --style minimal --no-open -o /tmp/out.pdf
```

**Full option reference:**
| Flag | Default | Description |
|------|---------|-------------|
| `--style` | `professional` | Theme preset |
| `--title` | Untitled | Title block + running header |
| `--author` | (none) | Shown below title |
| `--date` | (none) | e.g. "June 2026" |
| `--template` | `default` | `default`, `letter`, `report`, `memo` |
| `--font-size` | `11` | Body pt size |
| `--paper` | `us-letter` | `a4`, `us-legal`, etc. |
| `--no-title-block` | false | Suppress centered title block |
| `-o FILE` | `~/Desktop/<stem>.pdf` | Explicit output path |
| `--[no-]open` | opens | Auto-open after compile |

---

## Markdown supported

- `# H1` `## H2` `### H3`
- `**bold**` `_italic_` `***bold+italic***` `~~strikethrough~~`
- `` `inline code` `` and fenced ` ```lang ``` ` blocks
- `- ` unordered and `1.` ordered lists
- `> blockquotes`
- `[text](url)` links, `![alt](url)` images
- `---` horizontal rules

---

## Content validation (runs after every compile)

After compiling, `typst-qa --validate` compares the PDF body text word-for-word against the original source markdown:

- Extracts PDF body text, skipping headers, footers, page numbers, and the title block
- Normalizes both texts (strips markdown markup, lowercases, removes punctuation)
- Uses difflib sequence matching to find PDF words not covered by the original source
- Flags runs of 6+ consecutive unmatched words as **suspicious phrases**
- Reports coverage ratio (percentage of PDF body text that matched the input)

If suspicious phrases are found, a warning is printed to stderr with the phrases listed. The PDF is still written. The human should review it. This catches hallucinations introduced by the agentic rewrite step (Claude adding content it shouldn't have) or any unexpected conversion artifacts.

A clean result looks like: `"ok": true, "coverage": 1.0`

## Automatic visual QA (runs by default)

After the first compile, `~/bin/typst-qa` analyzes the PDF using PyMuPDF and detects:

- **Orphan headings**: heading in the bottom 22% of a page; injects `#pagebreak()` before it
- **Split sections**: page starts with ≤3 orphaned list items (tail of a section whose heading is on the previous page); pushes the whole section to the next page
- **Unbalanced pages**: previous page >70% full, next page <35% full; finds a section boundary to redistribute

Up to 3 compile passes run automatically. The template also sets `sticky: true` on all headings (Typst 0.14's keep-with-next) to prevent the most common orphan headings before QA even runs.

## After compiling

Report the Desktop path. If compilation fails, show the error and fix it.
