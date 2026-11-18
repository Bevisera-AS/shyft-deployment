# CLAUDE.md

@AGENTS.md

## Claude Code only

- AGENTS.md is the source of truth. Shared guidance goes there, not here.
- Before any `kubectl`/`helm` call that touches a cluster, check `kubectl config current-context` starts with
  `kind-`. If it doesn't, stop and ask.
