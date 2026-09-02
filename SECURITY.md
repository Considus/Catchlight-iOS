# Security

Catchlight is a zero-knowledge, end-to-end encrypted iOS app. Takes are encrypted on the device with standard cryptography (AES-256-GCM, HKDF and HMAC-SHA-256, all via Apple CryptoKit), and the key is derived from the user's Privacy Phrase and never leaves the device. There is no backend and there are no analytics, so if the encryption fails, there is nothing else standing between someone's notes and whoever is looking. If you have found a way past it, I want to hear about it.

## Reporting a vulnerability

Please report security issues **privately**, and don't open a public issue or a pull request.

Email **security@considus.com**. Tell me what you found, how to reproduce it, which version or commit it affects, and what it lets an attacker do.

I'll acknowledge it within **3 business days** and keep you posted while it's being looked at. This is coordinated disclosure, so please give me a reasonable amount of time to ship a fix before you make it public. You're welcome to the credit once it's out, or to stay anonymous, whichever you'd prefer.

## What's in scope

The iOS app and `CatchlightCore`, which means the cryptographic design, key management, local storage protection, and the file-based sync format.

Generally out of scope, anything that needs a jailbroken or otherwise compromised device, or physical access to a device that is already unlocked. Social engineering and denial of service are out too, along with findings in third-party platforms like Apple or whichever cloud provider the user picked, because those aren't mine to fix.

## Safe harbour

You won't face legal action from me or from Considus for research done in good faith, so long as you avoid violating anyone's privacy, avoid destroying data, and follow this policy.

## Supported versions

The `main` branch gets security fixes, and so will the current App Store release once Catchlight is released there.
