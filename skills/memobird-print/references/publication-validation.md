# Publication scope and validation

Prepared 2026-10-25. This release contains the existing `memobird-print` workflow and a `memobird-layout` companion extracted from its layout instructions and associated receipt CSS. No separate historical layout skill was found in the checked personal skill catalogs or original service project. The companion name and offline entry point are new packaging, not a claim about an older installation.

## Included and excluded

- Included: original BMP merge helper; full Swift service/core/transport/renderer/CLI source and core tests; dependency lockfile; sandbox entitlements; HTTP schema; markdown-it with its license; portable build/package helpers; receipt CSS; a newly written generic checklist; offline render entry point.
- Runtime source and core tests were copied byte-for-byte. Packaging helpers use explicit work/output directories and current-user paths; they do not depend on the original workstation.
- Excluded: installed apps/binaries, vendor SDK archives, credentials/tokens, device IDs, private IPs, job IDs/databases/logs, user documents/HTML/screenshots/print samples, commercial fonts, caches and unrelated personal skills.
- Installer code is supplied for future authorized deployment. It was not executed during publication, and the original local installation was not changed.
- Full file list: [file-manifest.txt](file-manifest.txt).

## Checks performed

- Both skill entry points passed the repository quick validator; the complete catalog passed `scripts/validate_skills.py` including Python smoke tests. Its existing loopback HTTP tests required execution outside the restricted socket sandbox; rerun passed.
- Three BMP helper tests: exact row preservation across 1600+230 rows, invalid-header rejection, no-overwrite behavior and combined-height guard. Three layout resource tests: local markup, network-reference rejection, symlink/CSS rejection. Python syntax checks passed.
- A dependency-free package assembled from bundled core/renderer source passed all **23 Swift tests** through XcodeBuildMCP on macOS arm64. This covers persistence/idempotency, protocol acknowledgement/recovery, bitmap format and power command encoding without creating a Bluetooth transport.
- The freshly built standalone renderer produced HTML, Chinese/English Markdown with table/code, and image previews. The generic checklist was 576×1090 with one BMP; its PDF was rasterized with the existing system tool and visually inspected for legibility, wrapping and clipping.
- A synthetic 576×1830 HTML document produced two stripes; the merge helper preserved every pixel row. Dedicated printer-BMP import produced one BMP byte-for-byte equal to the merged input. Existing output directory rejection passed.
- Mach-O linkage inspection of the standalone renderer found no CoreBluetooth dependency. No printing service was started or contacted for these previews.
- All bundled text was checked for workstation paths, private LAN IPs, device UUIDs and common credential/private-key patterns; files were checked for symlinks and user/binary outputs. Manual review retained generic protocol constants and synthetic fixtures, not device-specific payloads.

## Limits

No BLE scan/connect/print, device setting, service install/restart, permission change or new software installation was performed. Full service network-dependency build and signed app installation were not rerun; only the dependency-free core/renderer package was compiled. Portable build/package helpers passed syntax/CLI review but their complete signing/install path needs deployment validation.

This does not certify Intel Macs, macOS 14, another Mac's Bluetooth permission/network path, firmware variants, physical paper margins, arbitrary long-image reliability or complete paper output. The 4000-row limit is a software guard, not a measured hardware capacity. A device ACK means reception, and a rendered preview means no paper was printed.
