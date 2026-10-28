# Security policy

## Reporting a vulnerability

Please do **not** open a public issue, discussion or pull request for a
security problem.

- Preferred: GitHub private vulnerability reporting. Open the repository's
  **Security** tab and choose **Report a vulnerability**.
- Or email **security@hatamoto.dev**. Encrypt if you can; ask for a key in a
  first message without details.

Include what is affected (a file, manifest or script), how to reproduce it, the
impact you expect, and whether the problem is already public.

## What to expect

| Step | Target |
| --- | --- |
| Acknowledgement | within 3 business days |
| First assessment (accepted or not, severity) | within 10 business days |

We keep you informed while we work on it, agree a disclosure date with you, and
credit you unless you prefer otherwise. Please give us a reasonable time to
ship a fix before disclosing.

## Scope

In scope: this repository, the plugin and theme registry: the manifests, the
JSON schemas, the validation scripts and the CI workflows. Examples: a manifest
or script change that could get unreviewed code built or published, a
validator bypass, or a workflow that exposes secrets.

Out of scope:

- Vulnerabilities in Hatamoto core (the server, admin, API, plugin host, SDK,
  updater). Report those following the
  [core security policy](https://github.com/Zen-Labs-Corp/hatamoto/blob/main/SECURITY.md).
- Vulnerabilities in a listed plugin or theme. Report them to its author, whose
  repository the manifest points to. If a listed plugin is actively harmful,
  tell us at the address above and maintainers may remove its manifest.
