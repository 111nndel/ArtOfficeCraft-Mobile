# ArtOfficeCraft Mobile 0.45.0

> Android ARM64 development preview.

## What's New

- The heading list shrinks for short results and includes a clear-search button. Long outlines retain a bounded lazy viewport.
- Word View / Navigation now provides a filtered heading list, a body-text paragraph number, and beginning/end controls. A far target mounts immediately in the existing lazy document viewport and receives a subtle highlight.
- Heading levels follow the imported DOCX outline properties, document defaults and style inheritance, including custom/localized style names. Direct body-text level 9 suppresses an inherited heading. Style outline resolution is reused per style during preview generation.
- Navigation commits pending paragraph text before moving. Failed commits keep the draft and current editor available; successful changes remain undoable and saveable.
- Word exact-search results are reused across cursor moves and panel rebuilds. A changed query, paragraph draft or document snapshot invalidates them. Block lookup also uses the snapshot index.
- Adds a 2,000-paragraph independent DOCX navigation fixture, failure/Unicode/search-bound tests, and an AOT benchmark for repeated unchanged-query reads over 20,000 paragraphs. Benchmarks compare output and report timing without a pass/fail speed threshold.
- Native core 0.45.0, ABI 1. The four engine pins and 219-package Rust dependency graph are unchanged. No new runtime dependency, Kotlin code or appearance setting is added.

## Known Limitations

- Navigation covers main-body paragraphs. Tables, headers, footers, notes and embedded text boxes are excluded. Paragraph numbers are not page numbers.
- The heading list navigates existing outline levels; this does not insert or update a table of contents. Bold/larger text without an outline level is not treated as a heading.
- A changed search query/draft still scans text synchronously once. This change avoids repeated unchanged scans; it does not claim that initial DOCX parsing, edits or all large-document stalls are solved.
- Search/replace remains exact and case-sensitive, with the existing 10,000-result limit and protection checks. Layout and document-fidelity limits are unchanged.
- Benchmark timing is for Linux Dart AOT and synthetic text, not phone FPS. Android remains the only packaged app; Android 16 emulator checks do not establish physical-device performance.
