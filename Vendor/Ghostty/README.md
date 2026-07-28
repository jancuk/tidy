# GhosttyKit

Tidy embeds Ghostty's native terminal core through `GhosttyKit.xcframework`.

- Upstream: <https://github.com/ghostty-org/ghostty>
- Version: `v1.3.1`
- Commit: `332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28`
- License: MIT (see `LICENSE`)
- Build: native macOS arm64, `ReleaseSmall`, Zig 0.15.2

The framework was produced from the pinned upstream checkout with:

```sh
zig build \
  -Demit-xcframework \
  -Dxcframework-target=native \
  -Doptimize=ReleaseSmall
```

For a distribution that supports both Apple Silicon and Intel, rebuild with
`-Dxcframework-target=universal` and replace `GhosttyKit.xcframework`.
