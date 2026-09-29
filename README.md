# Maple Harness — binaries

<!-- This file is the template for the README of the public binaries repository,
     kinncj/maple-harness-dist. The release workflow renders v1.13.0 and pushes it. -->

Pre-built binaries of **Maple Harness**: a coding agent that works with GitHub Copilot's models, Claude and
models running on your own machine, a proxy that holds your sign-ins, and a web page for driving a session
from your phone.

This repository holds **binaries and installers only**, plus the built website. It has no source code, no issue
tracker and no build; releases are published to it automatically. The latest is **v1.13.0**.

**Website and documentation: <https://kinncj.github.io/maple-harness-dist/>**  ·  **Downloads: [latest release](https://github.com/kinncj/maple-harness-dist/releases/latest)**

## Contents

- [Install](#install)
- [Sign in and connect models](#sign-in-and-connect-models)
- [Update](#update)
- [Licence](#licence)
- [Support](#support)

## Install

```sh
# macOS and Linux
curl -fsSL https://raw.githubusercontent.com/kinncj/maple-harness-dist/main/install.sh | bash
```

```powershell
# Windows
irm https://raw.githubusercontent.com/kinncj/maple-harness-dist/main/install.ps1 | iex
```

No account or token is needed. The installer detects your platform, downloads the programs, checks each one
against the release's `SHA256SUMS`, and refuses to install if a file is missing or does not match. It installs
to `/usr/local/bin`; change that with `--install-location DIR`, and choose a release with
`MAPLEHARNESS_VERSION=vX.Y.Z`. To read the installer before running it, open `install.sh` in this repository.

Platforms: macOS (Apple silicon and Intel), Linux (amd64, arm64), Windows (amd64).
[Full install guide](https://kinncj.github.io/maple-harness-dist/docs/install.html).

## Sign in and connect models

Start the proxy, then sign in or add a model server:

```sh
maple-proxy serve                            # then open http://127.0.0.1:11539
maple-harness auth login github-copilot      # a browser sign-in
maple-harness auth login claude              # an Anthropic API key
maple-harness                                # start the agent in your project
```

- [Getting started](https://kinncj.github.io/maple-harness-dist/docs/getting-started.html)
- [Signing in to GitHub Copilot or Claude](https://kinncj.github.io/maple-harness-dist/docs/sign-in.html)
- [Setting up the proxy](https://kinncj.github.io/maple-harness-dist/docs/proxy.html)
- [Connecting Ollama, LM Studio or any OpenAI-compatible endpoint](https://kinncj.github.io/maple-harness-dist/docs/endpoints.html)
- [Controlling a session from your phone](https://kinncj.github.io/maple-harness-dist/docs/remote-control.html)

## Update

```sh
maple-harness update --check    # is there a newer release?
maple-harness update            # install it, verified against SHA256SUMS
maple-proxy update              # the proxy updates itself the same way
```

## Licence

Copyright © 2026 Kinn Coelho Juliao. All rights reserved.

- **Free for non-commercial use** — personal, hobby, education, research and non-profit use — and you may
  redistribute the unmodified binaries with the licence text attached.
- **Commercial use requires access granted by the owner**; otherwise a commercial agreement has to be
  negotiated first.
- The source code is not licensed for reuse.

The full terms are in [LICENSE](LICENSE), and a copy is attached to every release. The licences of the
third-party software inside the binaries are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Support

Write to Kinn Coelho Juliao <kinncj@gmail.com> — for help, for access, or to begin a commercial conversation.

Made with ❤️ by Kinn Coelho Juliao in Ottawa, eh — fuelled by double-doubles, bud. 🍁
