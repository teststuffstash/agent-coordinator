# agent-coordinator — Claude Code as the coordinator, in a pod.
#
# Bundles just what the coordinator runbook needs: the `claude` CLI (subscription auth via
# CLAUDE_CODE_OAUTH_TOKEN), kubectl (talks to the cluster via the pod's ServiceAccount), gh + git
# (read/label issues, merge PRs), and python3/jq (the budget estimator + JSON). The homelab repo
# (brief + launchers + estimator) is cloned at runtime by `agents/coordinator-session.sh`, not baked
# in, so the coordinator always runs the current main.
#
# Built + pushed by CI on every push to master (.github/workflows/build-image.yaml); `scripts/
# build-image.sh` is the local mirror. homelab is the *consumer* — it references the image by tag.
FROM node:22-bookworm-slim

ARG KUBECTL_VERSION=v1.36.1

# OS tools + gh (official apt repo) + kubectl (pinned to the cluster minor).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git jq python3 gnupg less bash; \
    # gh
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; apt-get install -y --no-install-recommends gh; \
    # kubectl
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"; \
    chmod +x /usr/local/bin/kubectl; \
    # s5cmd — the transcript-capture S3 client (homelab docs/agents/observability-and-retro.md §A1):
    # the reviewer pod, the coordinator exit-trap and the transcripts-sync CronJob all upload with it.
    # Pinned release + checksum (static Go binary; not packaged in Debian).
    curl -fsSLo /tmp/s5cmd.tgz "https://github.com/peak/s5cmd/releases/download/v2.3.0/s5cmd_2.3.0_Linux-64bit.tar.gz"; \
    echo "de0fdbfa3aceae55e069ba81a0fc17b2026567637603734a387b2fca06c299b4  /tmp/s5cmd.tgz" | sha256sum -c -; \
    tar -xzf /tmp/s5cmd.tgz -C /usr/local/bin s5cmd; \
    chmod +x /usr/local/bin/s5cmd; rm /tmp/s5cmd.tgz; \
    # Claude Code CLI
    npm install -g @anthropic-ai/claude-code; \
    rm -rf /var/lib/apt/lists/*

# Pre-seed the three things that otherwise stop a fresh container on an interactive prompt, so it
# comes up silent like the homelab jail:
#   • onboarding wizard  → ~/.claude.json hasCompletedOnboarding
#   • "Is this a project you trust?"  → projects./work/homelab.hasTrustDialogAccepted (the coordinator
#     always clones homelab there). NB --dangerously-skip-permissions does NOT cover this one.
#   • the Bypass-Permissions WARNING (the flag alone does NOT suppress it) → settings.json
#     skipDangerousModePermissionPrompt:true + a permissive permissions.allow — copied from the jail's
#     ~/.claude/settings.json, which is how it never prompts.
# Auth comes from CLAUDE_CODE_OAUTH_TOKEN at runtime. Owned by the non-root node user (uid 1000).
RUN mkdir -p /home/node/.claude /work \
    && printf '%s\n' '{"hasCompletedOnboarding":true,"projects":{"/work/homelab":{"hasTrustDialogAccepted":true}}}' \
        > /home/node/.claude.json \
    && printf '%s\n' '{"permissions":{"allow":["Bash(*)","Read(*)","Edit(*)","Write(*)","WebSearch(*)","WebFetch(*)"]},"skipDangerousModePermissionPrompt":true}' \
        > /home/node/.claude/settings.json \
    && chown -R node:node /home/node/.claude /home/node/.claude.json /work

# A long coordinator session outlives a 1h GitHub App token. ESO refreshes it in the coordinator-git
# Secret (~hourly); the launcher mounts that Secret as a FILE (kubelet keeps it current), so shadow
# `gh` with a wrapper that reads the LIVE token from $GH_TOKEN_FILE per call — never a stale env
# snapshot. Falls back to the inherited GH_TOKEN env when the file is absent (older launcher).
RUN printf '%s\n' \
      '#!/bin/sh' \
      ': "${GH_TOKEN_FILE:=/var/run/coordinator-git/GH_TOKEN}"' \
      'if [ -r "$GH_TOKEN_FILE" ]; then GH_TOKEN="$(cat "$GH_TOKEN_FILE")"; export GH_TOKEN; fi' \
      'exec /usr/bin/gh "$@"' \
      > /usr/local/bin/gh && chmod +x /usr/local/bin/gh

# Workflow templates run scripts as `bash -lc '…'` (the container's direct command → SHLVL=1).
# At login-shell EXIT, Debian's skel ~/.bash_logout runs clear_console, which fails without a
# console tty; with `set -e` active that failure OVERRIDES an explicit `exit 0` → rc 1. Every
# idempotent skip path (`echo …; exit 0`) reported Failed while doing exactly its job; the
# normal path `exec`s away and never runs logout processing, which is why only skips broke
# (homelab TICK-LOG 2026-07-25; fix verified in-image: same shape, no logout file → rc 0).
RUN rm -f /home/node/.bash_logout /root/.bash_logout /etc/bash.bash_logout

USER node
ENV HOME=/home/node
WORKDIR /work
