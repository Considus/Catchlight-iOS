# Security Policy

Catchlight is a zero-knowledge, end-to-end encrypted iOS app. Takes are encrypted on-device
with standard cryptography (AES-256-GCM, HKDF, HMAC-SHA-256 via Apple CryptoKit); the key is
derived from the user's Privacy Phrase and never leaves the device. There is no backend and
no analytics.

The source is published publicly for **independent review only**; it is proprietary and not
open source (see [`LICENSE`](LICENSE)). Reviewing the code for vulnerabilities is exactly the
kind of scrutiny we welcome.

## Reporting a vulnerability

Please report security issues **privately** — do not open a public report, and note that
pull requests are not accepted (issues are disabled on this repository).

- **Email:** security@considus.com
- **GitHub:** use the repository's private **“Report a vulnerability”** advisory form
  (Security tab) if you prefer.
- **Include:** a description, steps to reproduce, the affected version or commit, and impact.

We aim to acknowledge within **3 business days** and to keep you updated as we investigate.
We practise **coordinated disclosure**: please give us reasonable time to ship a fix before
any public disclosure. We're glad to credit you, or keep you anonymous — your choice.

## Scope

**In scope:** the iOS app and `CatchlightCore` — the cryptographic design, key management,
local storage protection, and the file-based sync format.

**Generally out of scope:** issues requiring a jailbroken/compromised device or physical
access to an unlocked device; social engineering; denial of service; and findings in
third-party platforms (Apple, a user's chosen cloud provider) outside our control.

## Safe harbour

We will not pursue legal action against researchers who act in good faith, avoid privacy
violations and data destruction, and follow this policy.

## Supported versions

The latest App Store release and the `main` branch receive security fixes.
