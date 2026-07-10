# SECURITY

## Secrets

- No secrets in code, comments, docs, or commits.
- Ollama API keys live in **Keychain** (`KeychainStore` / `OllamaSecrets`).
- Never commit `.env`, key files, or vault contents.

## Network

- Only the configured Ollama base URL is contacted (`/api/tags`, `/api/chat`).
- Cloud is opt-in (endpoint + key). Local default: `http://localhost:11434`.

## Filesystem

- App sandbox is **disabled** so the user-configured vault path is writable.
- Writes limited by policy to Knowledge `raw/` and `wiki/` (and outputs if used).
- Never delete vault content from the app.

## Git / agents

- No force-push to shared main without explicit human confirmation.
- No `git reset --hard` or vault history rewrites as a "fix."
- Report security issues privately to the maintainer when possible.

## Data

- No real third-party PII in fixtures.
- Compile state (processed source hashes + article body hashes) is machine-local Application Support, not the synced vault.
