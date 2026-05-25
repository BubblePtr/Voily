# Sparkle

This directory vendors the official Sparkle 2.9.2 Swift Package Manager binary distribution so Voily builds do not depend on SwiftPM downloading Sparkle's binary artifact during CI or release builds.

- Source: `https://github.com/sparkle-project/Sparkle/releases/tag/2.9.2`
- Artifact: `Sparkle-for-Swift-Package-Manager.zip`
- SHA-256: `b83e37436774556ed055e0244b297ef2c790e0737393bf65bf495fcbba6eed65`

Keep `LICENSE` with the vendored artifact. To update Sparkle, replace the zip with the new official SPM artifact, update the checksum above, and run `make generate` plus the app build/test checks.
