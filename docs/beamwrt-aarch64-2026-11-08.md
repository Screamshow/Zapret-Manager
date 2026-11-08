# Zapret / Zapret2: unified APK aarch64

Status: signed package set published and publicly verified; panel 4.71.3 prepared on dev.
The operator approved the exact update text below on 2026-11-08.
Panel version 4.71.3 is prepared for publication after package verification.

## Finding

Customer output: Beam WRT 1.5.5, OpenWrt 25.12.6, qualcommbe/ipq95xx,
`DISTRIB_ARCH=aarch64_cortex-a73`, but `apk --print-arch` reports `aarch64`.
The pinned remittor release has no A73 ZIP. Both remittor's generic APK and
Routerich's Zapret2 APK declare CPU-specific architecture names, not `aarch64`.

## Candidate

- Native package architecture determines use of the new unified ARM64 path.
- Zapret: remittor 72.20260307 generic ARMv8 payload, APK revision r100.
- Zapret2: Routerich 1.0.5.2 payload, APK revision r100.
- LuCI packages retain noarch and have corresponding r100 revisions.
- These are repackaged upstream binaries, not newly compiled core versions.
- Source downloads are pinned by SHA-256. Package payloads, symlinks, file
  modes, dependencies, provides, lifecycle scripts and triggers are preserved
  and compared after extraction of the rebuilt package.
- The packaging tool checks AArch64 ELF headers. The inert original Huawei
  ARM32 sample module under Zapret's files/ is preserved as an upstream sample.
- Four packages signed with the existing mirror key; private keys remain on
  that host. Signing output and all four signature verifications passed.
- Runtime pins cover signed APK size and SHA-256. The exact output manifest
  is `packages/unified-aarch64/20261108/manifest.json`.
- Dependency simulation precedes installation and stopping an existing
  runtime; a failure aborts. No architecture override or repository rewrite.
- Both component packages are installed together in one APK transaction.
- Existing CPU-specific paths remain; A73 ZIP fallback is allowed only if
  the package manager explicitly accepts an available architecture.
- Zapret2's A53-only gate and UI hints now also allow unified APK aarch64.
- Missing legacy assets (404/410) terminate retries. ZIP extraction and
  expected core package presence are checked before stopping Zapret.

## Verification

- Existing backend behavior and panel contract tests passed, including shell
  syntax and route/RPC contracts.
- New tests cover APK-native architecture detection, Zapret2 support gates,
  explicit permitted/rejected legacy fallback, both package pairs, corrupted
  content, failed downloads and dependency failures. Legacy 404 causes one
  attempt; 504 causes five, without stopping an installed service.
- Existing UI-render test passed for all five LuCI pages, five Web pages and
  five shell routes (isolated jsdom 26.1.0 installation under parent tmp/).
- Signed artifacts match the sizes/hashes pinned in the backend.
- Real apk-tools 3.0.5 simulated and installed each signed core/LuCI pair
  into separate temporary roots with native architecture aarch64. Subsequent
  package database reads passed. Scripts were disabled and dependency names
  supplied by a noarch fixture: this proves APK acceptance/registration, not
  actual BeamWRT dependency resolution or service startup.
- This check caught non-root payload ownership and YAML literal-description
  trailing newlines during packaging; both fixed before final signing. Builder
  now requires root or `unshare -r` and compares complete ADB path metadata.
- Under isolated QEMU AArch64 10.2.1 with official OpenWrt 25.12.5 musl and
  libraries, nfqws reports 72.20260307 (ef637c4), nfqws2 reports v1.0.5.2
  (6b6c63e, lua compatibility 6), and the Zapret2 management ELF prints help.
- QEMU was downloaded/unpacked under parent tmp/, without system installation.
- Existing OpenWrt 25 VM board/package baseline inspected read-only. No VM
  package/service/configuration changes or ARM package installation attempted.
- No installation on the operator or customer router. Customer will perform
  final BeamWRT installation. QEMU version/help checks do not prove netfilter,
  live DPI bypass, dependency availability or runtime startup on that firmware.
- `git diff --check` passed. Panel release prepared on existing dev.

## Staging and remaining publication steps

Signed packages: parent `tmp/zms-aarch64-20261108/packages/` and mirror host
`/root/zms-aarch64-20261108/input/`. Package builder lives under tools/.
The manifest records source URLs/hashes and the intended immutable mirror URLs.
All four public package URLs were downloaded again; sizes and SHA-256 match
the runtime pins and published manifest. Keep the exact
signed files; rebuilding/resigning requires recalculating the pins.

After the operator agrees the proposal text: select the next available panel
version, insert agreed changelog, prepare release commits under the repository's
workflow, publish the exact packages and verify public sizes/hashes/signatures,
then publish the panel and verify its mirror and direct fallback. User approval
of text must precede those publication operations.

## Approved update text

Установка Zapret и Zapret2 на BeamWRT с архитектурой APK aarch64

## Publication verification

All four APK signatures verified again before atomic publication of the
immutable 20261108 package directory. Public manifest reports published; all
four public downloads matched size/hash pins. Changelog for panel 4.71.3
contains only the exact operator-approved line above. Automatic approval review
requires explicit user approval to integrate this release into main.
