# ArtOfficeCraft Mobile 0.59.0

## What's New

- Word shows the body word count in View / Navigation, including changes to the paragraph being edited. Hyphenated words and contractions count as one.
- Excel adds Average, Count numbers, Minimum and Maximum in Formulas / Functions. Select an empty cell below or to the right of a group of numbers. The result is an editable XLSX formula and supports undo and redo.
- PowerPoint searches slide titles and text boxes without case sensitivity. Tap a result to open the slide.
- PDF and PowerPoint can jump to the first or last page or slide without entering a number.
- Files and Favorites remember their sort order. Large libraries check their working copies in one directory scan. Theme, language and file order use a shared Dart preference writer.
- App 0.59.0+66, ARM64 versionCode 2066. Native core 0.59.0, ABI 1.

## Known Limitations

- The Word count covers body paragraphs. Tables, headers and footers are excluded. Languages without word separators can produce different counts from desktop Word.
- PowerPoint searches text available in the preview, including up to 120 top-level objects per slide. Image text and speaker notes are excluded.
- Quick Excel formulas use adjacent numeric cells above the result first, then to the left. The destination must be empty and unmerged.
