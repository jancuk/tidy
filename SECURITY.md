# Security

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository. Do not
open a public issue containing credentials, private data, or exploit details.

Include the affected version, reproduction steps, impact, and any suggested
mitigation. Maintainers should acknowledge a complete report promptly and keep
the report private until a fix is available.

## Security model

- Provider, MCP, Jira, and Asana secrets are stored in the macOS Keychain, not
  in repository files or `UserDefaults`.
- Remote MCP endpoints must use HTTPS. Plain HTTP is allowed only for loopback
  development servers.
- Authenticated HTTP requests do not follow cross-origin redirects.
- MCP discovery only permits tools that pass Tidy's read-only checks. Treat the
  configured MCP server as trusted infrastructure; tool metadata is
  server-supplied and cannot make a malicious server safe.
- Slack notification integration performs searches and reads only. It does not
  post messages, replies, reactions, or other Slack mutations.
- Local history and cache files use owner-only permissions. Clipboard data and
  AI request metadata remain sensitive local data and should not be shared.
- Ask AI sends the selected text and explicitly selected folder context to the
  configured provider. Common credential and local-configuration files are
  excluded, but users should still review the selected scope before sending it.
- File Tidy confines apply and undo operations to the selected folder.

## Public contributions

Never commit API keys, OAuth tokens, cookies, private MCP endpoints, `.env`
files, signing configuration, exported user data, or fixtures containing real
people, organizations, channels, projects, or messages. Use reserved example
domains and synthetic data in documentation and tests.
