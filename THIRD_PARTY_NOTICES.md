# Third-party licenses and attribution

This is an independent community project. It is NOT affiliated with, sponsored,
certified, or endorsed by Microsoft, the ArtCraft Team, or the original Rust
project authors. Their names identify dependencies and document formats.
No third-party official logos or installers are distributed here.

This repository stores our Flutter, FFI and integration source, not copies
of the four upstream source trees. The source updater retrieves tagged commits
directly from their original public repositories.

| Dependency | Original authors | License | Source |
| --- | --- | --- | --- |
| WordCraft | ArtCraft Team and WordCraft contributors | MIT or Apache-2.0 | https://github.com/storytold/wordcraft |
| GridCraft | ArtCraft Team and GridCraft contributors | MIT or Apache-2.0 | https://github.com/storytold/gridcraft |
| DeckCraft | ArtCraft Team and DeckCraft contributors | MIT or Apache-2.0 | https://github.com/storytold/deckcraft |
| PDFCraft | ArtCraft Team and PDFCraft contributors | MIT or Apache-2.0 | https://github.com/storytold/pdfcraft |

Exact revisions are recorded in upstream/engines.lock.json.

Copies of each upstream NOTICE, LICENSE-MIT, and LICENSE-APACHE from pinned
revisions are included in licenses/upstream/. Selected crates from all four
engines are compiled into Android binaries. A binary release must include all required license
and notice text, including for transitive dependencies actually bundled.
Asset, font, and icon licensing must be re-audited whenever included.

Flutter, Dart and flutter_file_dialog are separately licensed components;
consult their respective licenses and resolved dependency manifests.
Rust package dependencies are described in native/artoffice_core/Cargo.lock.
`tools/collect_rust_licenses.py` collects the resolved Android Rust dependencies'
license and notice texts into `assets/legal/rust-licenses.json`. This file is
bundled in the APK and exposed through the About / Licenses screen. The collector
fails if a resolved package has no license text. Flutter's normal license registry
also remains available.
Before any binary production release, review a complete dependency license
report. No user-supplied video, proprietary Microsoft resources, ArtCraft
branding, or original third-party installers are bundled in this source repository.

The original integration code is distributed under the repository's MIT LICENSE.
This does not override any third-party copyright or trademark requirements.
