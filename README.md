# agent-coordinator

The homelab agent platform's **coordinator image**. One small repo, one responsibility: build and
publish the container the *coordinator* runs in. Design + operation live in the
[homelab repo](https://github.com/teststuffstash/homelab) (`agents/coordinator/`); this repo only
produces the artifact — the sibling of [`agent-runtime`](https://github.com/teststuffstash/agent-runtime)
(which builds the *worker* image, `agent-base`).

## Why its own repo

Same reason as `agent-runtime`: the image needs a build-and-publish pipeline (docker → ghcr,
versioned, Renovate). Bolting that onto the homelab IaC monorepo would mean path filters and "what
does this push build/deploy?" rules on a repo that otherwise just applies Tofu/Ansible. Here the rule
is trivial: **every push to `master` builds**. homelab is the *consumer* — `agents/coordinator-session.sh`
references the image by tag.

## `coordinator`

`FROM node:22-bookworm-slim` + the **Claude Code CLI** (`@anthropic-ai/claude-code`) and the tools the
coordinator runbook needs: `kubectl` (talks to the cluster via the pod's ServiceAccount), `gh` + `git`
(read/label issues, open/merge PRs), `python3` + `jq` (the budget estimator + JSON). It bakes **no**
homelab content — the brief, launchers, and estimator are cloned at runtime from homelab, so the
coordinator always runs the current main.

Auth is the operator's **Claude subscription**: a `claude setup-token` OAuth token mounted as
`CLAUDE_CODE_OAUTH_TOKEN` (the launcher wires this; the image just pre-seeds onboarding). The image
deliberately does **not** carry `ANTHROPIC_API_KEY` — it would take auth precedence over the token.

## Versioning

The image tag is **content-addressed by `coordinator/Dockerfile`**: `YYYY-MM-DD-<dockerhash8>`.
`:latest` tracks `master`. ⚠️ `gh` (apt) and `claude` (npm) install at `@latest`, so the *content*
can drift without a Dockerfile change; pin them if you need bit-reproducibility.

## Build

```sh
bash scripts/build-image.sh             # build only (needs docker)
PUSH=true bash scripts/build-image.sh   # build + push (after `docker login ghcr.io`)
```

CI does this on every push to master (`.github/workflows/build-image.yaml`), on the self-hosted
`homelab-ephemeral` ARC runner, authenticating the ghcr push with the job's built-in `GITHUB_TOKEN`
(`packages: write`) — **no extra secret/token**.

## One-time: make the package public

After the first successful build, make `ghcr.io/teststuffstash/agent-coordinator` public (Package
settings → Change visibility), or the in-cluster pull `ImagePullBackOff`s (public repo → public
package is simplest; the alternative is an imagePullSecret).
