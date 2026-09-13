# 3x-ui exporter changelog

## Exporter 1.2.0 / Windows helper 1.0.0 — 2026-09-13

- Download exports to a chosen Windows directory with one local PowerShell
  command and one SSH connection, using SSH aliases, ports, keys or passwords.
- Transfer a ZIP with size and SHA-256 verification and automatic remote cleanup;
  failed downloads remove the local partial file and preserve existing backups.
- Support root and passwordless sudo without installing remote scripts or
  automatically installing missing dependencies.
- Stop and clean up if ZIP creation fails, including after a partial file is written.

## Exporter 1.1.0

- Add interactive temporary ZIP export with a 15-minute download window and cleanup.

## Exporter 1.0.0

- Export local SQLite inbound configuration and subscription/node links.
