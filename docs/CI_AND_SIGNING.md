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
3. An unsigned offline ARM64 release APK, with checks for application identity,
   disabled Android debugging, permissions, ZIP integrity, native 16-KiB alignment
   and licence texts. Candidate artifacts expire after seven days.
4. For version tags in the original repository only, a separate job downloads
   that run's candidate and signs it with the established preview key. It does
   not check out or run project source. Only this job receives a writable token
   and the environment signing secret. It publishes APK/hash/provenance/notices
   through GitHub CLI. A published release is never overwritten by a rerun.

Jobs use GitHub-hosted Ubuntu 24.04, Java 21 and Android API/build-tools 36.
The first full successful cloud run was
[41706407847](https://github.com/111nndel/ArtOfficeCraft-Mobile/actions/runs/41706407847):
91 Flutter tests, 17 Rust tests, four updater tests, clean analysis and an ARM64
APK passing package/offline/16-KiB/94-licence checks. The Windows fallback
publisher's certificate guard was separately exercised with a valid original-key
APK (accepted) and a valid APK signed with a disposable key (rejected before
publication). The disposable test key was then deleted.

Actions are pinned to full upstream commit SHAs. The signing environment
`android-preview` permits only tags matching `v*-alpha.*`; no branch or PR
deployment is allowed. Test/build jobs receive no signing key. No
`pull_request_target`, self-hosted runner or automatic merge is used.

The Android 16 job covers editor scenarios, screenshots and an in-place upgrade
of the ordinary app. See [Android CI coverage](android-ci.md). Physical-device
checks and visual inspection of representative documents are separate QA work.
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
The Windows fallback publisher also checks this exact certificate before it can
create a release. Use its `-VerifyOnly` switch to check an APK without publishing.

The signing key is provided to the isolated publishing job through a protected
GitHub environment secret; it is not stored in the repository. The existing
preview certificate is a **development** identity and must not be used as a
production or Google Play signing key.

Keep independently encrypted backups of signing credentials and recovery
passphrases in private, access-controlled storage. Never publish backup
filenames, storage locations, password locations, credentials, or recovery
instructions in this repository. The public certificate fingerprint cannot be
used to reconstruct the private key.

Any future change to signing identity requires a separate, carefully planned
migration to avoid breaking updates for existing installations.


### Release without a contributor PC

A push to `release-request/v<VERSION>-alpha.<N>` requests a preview. A separate
job, with no checkout and no signing environment, creates a missing tag at that
exact SHA and dispatches the full CI workflow against the tag. An existing tag
pointing elsewhere is rejected. The tag workflow repeats all Flutter/Rust/package
and Android 16 checks before publication; old branch artifacts are not reused.

Only the allowed tag context enters the protected `android-preview` environment.
Its deployment rules and signing secret stay unchanged. The isolated publisher
retains its no-checkout rule, existing certificate/hash/source checks and refusal
to overwrite a published release. No signing key is exposed to the request job or
test jobs. Ordinary branches and PRs cannot enter the signing environment.
