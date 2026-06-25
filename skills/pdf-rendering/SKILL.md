---
name: pst:pdf-rendering
description: Server-side PDF generation with Puppeteer and Handlebars. Auto-applied by the pst shim on every PDF-rendering change; also invocable directly.
auto:
  extensions: [js, mjs, hbs, handlebars, html]
  detect: ["**/*pdf*.js", "**/*.hbs", "**/*.handlebars", "**/*template*.html"]
---

# Server-side PDF Generation Cheat Sheet

Source: Puppeteer PDF and network interception docs + Handlebars guide

Question: Will identical input render identical PDFs without leaks or remote dependencies?

Favor:
- Compile Handlebars templates once and pass plain data objects.
- Keep `{{ }}` escaping on; validate data before render.
- Use local assets, fonts, and CSS only.
- Set explicit format, margins, and `printBackground`.
- Wait for content and fonts before `page.pdf()`.
- Close page, context, and browser in `finally`.
- Cap concurrency and set timeouts.
- Fix locale, timezone, and clock in tests.

Forbid by default:
- `{{{` or `SafeString` on untrusted data.
- Remote CDN assets in templates.
- Calling `page.pdf()` without options.
- Leaving browser instances open on error paths.
- Writing temp files outside a managed directory.
- Mixing template compilation with request globals.

CI:
- `eslint . --max-warnings 0`
- `! git grep -nP "\\{\\{\\{|\\bSafeString\\b|https?://|page\\.pdf\\(\\s*\\)" -- '*.hbs' '*.handlebars' '*.html' '*.js' '*.mjs'`

Agent protocol:
1. Lock down templates and input data first.
2. Make rendering deterministic.
3. Close every browser resource on every path.
4. Preserve behavior.
