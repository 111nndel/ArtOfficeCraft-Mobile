# Continuous checks and preview signing

The workflow in `.github/workflows/ci.yml` runs on development/main pushes and
pull requests. Tag pushes matching `v<app-version>-alpha.<number>` additionally
sign and publish a preview. Manual dispatch becomes available after the workflow
is present on the repository's default branch; branch pushes work beforehand.

## What runs

1. Flutter 3.47.9 (framework commit
   `c197ca5199e9ee5661e865596c9c07294dfab51c`), locked Pub dependencies,
   Flutter analysis/tests and Python updater tests.
2. All four engine sources staged from the reviewed commits in
   `upstream/engines.lock.json`, Rust 1.99.1 tests and an ARM64 release core built
   with Android NDK 28.2.13676358. Cargo uses `--locked`; engine pins are never
   automatically advanced. Licence texts are regenerated from resolved sources.
3. An ordinary offline ARM64 profile APK, with application identity, signature,
   permissions, ZIP integrity, native 16-KiB alignment and licence checks.
   Candidate artifacts expire after seven days. They use an ephemeral runner
   debug certificate and are for inspection, not updates to existing installs.
4. For version tags in the original repository only, a separate job downloads
   that run's candidate and signs it with the established preview key. It does
   not check out or run project source. Only this job receives a writable token
   and the environment signing secret. It publishes APK/hash/provenance/notices
   through GitHub CLI. A published release is never overwritten by a rerun.

Jobs use GitHub-hosted Ubuntu 24.04, Java 21 and Android API/build-tools 36.
Actions are pinned to full upstream commit SHAs. The signing environment
`android-preview` permits only tags matching `v*-alpha.*`; no branch or PR
deployment is allowed. Test/build jobs receive no signing key. No
`pull_request_target`, self-hosted runner or automatic merge is used.

The workflow does **not** currently run Android emulator tests, visual checks,
ordinary-app force-stop/SAF scenarios or physical Vivo tests. Those remain separate
QA requirements. A successful cloud build is not evidence of full editor fidelity.
Hosted runner images, Java security patches and downloaded engine artifacts can
change, so this is a version-pinned pipeline, not a claim of bit-for-bit rebuilds.

## Permanent identity of existing previews

Application ID: `ai.artofficecraft.artofficecraft_mobile`.

Certificate SHA-256:
`4e16cc21d19cdcde840361cd34fbdcfbf901b48c6f8ff66ef473e7ddf4a05005`.

The existing certificate is valid from 2026-11-02 through **2056-10-25** and has
an RSA-2048 key. This is the original **development** certificate, not a new
production/Play signing identity. Keeping it preserves APK update compatibility.
The workflow rejects an APK signed with any other certificate. Do not regenerate
it, delete the source keystore, or silently replace it with a runner-generated key.

The private keystore is held in GitHub environment secret
`AOC_PREVIEW_KEYSTORE_BASE64`, not in Git. Base64 is transport encoding, not
encryption; GitHub encrypts stored secrets. The established development key uses
alias `androiddebugkey` and the standard development-store password. It must not
be presented as production-grade key protection or used as a Play release key.

A separate private copy is kept outside the source checkout on the build PC.
An encrypted PKCS12 backup of the same key is also saved in ChatGPT as
`ArtOfficeCraft_Signing_Backup_2026-11-03.zip`. Its independently generated
256-bit random password is **not** in the archive, chat or repository; it is in
`%LOCALAPPDATA%\ArtOfficeCraft\Signing\backup-password.txt` on the build PC,
inside a current-user/SYSTEM-only directory. The backup was restored into a
temporary keystore and successfully signed an APK with the original fingerprint;
the temporary keystore was deleted. The owner must move the backup password to
an independent password manager before retiring or losing that PC.
Public certificate fingerprints and this document can be stored or shared safely;
they cannot recreate a lost private key. ChatGPT file storage does not make a
signing key permanent, and a chat should not be the only recovery location.
An independent encrypted backup and its password must be retained by the owner
before retiring that PC or changing accounts. Expiration/production-key migration
requires a separately planned signing transition, not a changed fingerprint.
