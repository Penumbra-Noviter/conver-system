# Security Policy

## Supported Versions

Conver System is a single-maintainer project. Security updates are provided
for the **latest released version only** — older releases do not receive
security patches, so please always upgrade to the newest release.

| Version | Supported          |
| ------- | ------------------ |
| 0.5.x   | :white_check_mark: (latest) |
| 0.4.x   | :x:                |
| 0.3.x   | :x:                |
| < 0.3   | :x:                |

## Reporting a Vulnerability

**Please do not file a public GitHub issue for a security vulnerability.**

To report a vulnerability privately:

1. Go to the repository's **Security** tab:
   <https://github.com/Penumbra-Noviter/conver-system/security>
2. Click **Report a vulnerability** (private vulnerability reporting) and
   describe the issue.

Please include:

- The Conver System version you are using (shown in the About dialog / app
  title, or in `src-tauri/tauri.conf.json`).
- Steps to reproduce, or the affected scenario.
- The impact, if you have one (e.g. data exposure, code execution).

**Scope:** this channel covers vulnerabilities in Conver System itself (its
code and shipped configuration). Vulnerabilities in third-party dependencies
should be reported to the respective upstream projects.

### What happens next

- **Acknowledgment:** you will receive a response within **3 business days**.
- **Assessment:** expect an update — accepted or declined — within
  **7 business days**; complex issues may take longer.
- **Accepted:** the fix will be released as soon as possible, and a security
  advisory will be published with credit to you (unless you prefer to remain
  anonymous), typically after the patched release is available.
- **Declined:** if the report turns out to be a false positive, a design
  limitation, or out of scope, we will explain why. After the report is
  closed, you are free to disclose it publicly.

General bugs and feature requests belong on
[GitHub Issues](https://github.com/Penumbra-Noviter/conver-system/issues),
not on this channel.
