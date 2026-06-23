# ENGINE_SOURCE — vendored, frozen, read-only

This twin depends on the **frozen** `neuram_v2_threshold` engine. The engine is
**vendored** (copied) under [`lib/engine/`](lib/engine/) so this repository clones and runs
**offline and deterministically** without fetching anything.

- **Engine repository:** https://github.com/zzabisagent-lab/neuram_v2_threshold
- **Pinned commit (frozen):** `45ad1c0008af70ea8d901c93b7acf58a4979301f`
- **Engine status:** frozen. Its §7 pre-registration passed 11/11. It is **not**
  changed by this twin.

## Rules

- Files under `lib/engine/` are a **read-only mirror**. The twin **must not modify the
  engine** — it calls only the engine's public API.
- Each vendored file carries a 2-line `//VND …` header recording the pinned SHA and
  the SHA-256 of its body (LF-normalized, excluding the `//VND` lines). Apart from
  that header, every vendored file is **byte-identical** to the engine at the pinned
  commit (verified by REG-2 against `lib/engine/VENDOR_MANIFEST.json`).
- If the engine is found to be missing something the twin needs, the twin **reports
  it — it does not patch the engine.**

## Verifying the vendor

`lib/engine/VENDOR_MANIFEST.json` lists the SHA-256 of each vendored body. The bench
`bin/twin_test.dart` (REG-2) recomputes those hashes from the files on disk and
fails if any engine file was altered beyond its header.
