#!/usr/bin/env bash
set -euo pipefail

# ─── Helpers ──────────────────────────────────────────────────────────────────

log() { printf '\033[36m▸\033[0m %s\n' "$1"; }
err() { printf '\033[31m✗\033[0m %s\n' "$1" >&2; }

is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    true | 1 | yes) return 0 ;;
    *) return 1 ;;
  esac
}

# Split a comma- or space-separated list into individual args.
split_list() {
  printf '%s' "${1:-}" | tr ',' ' ' | xargs -n1 2>/dev/null || true
}

# The cxs CLI prints a spinner status line (e.g. "  Deploying...") to stdout
# before its --json payload when not attached to a TTY. Slice from the first
# line that begins a JSON object/array so jq only sees valid JSON.
extract_json() {
  sed -n '/^[[:space:]]*[{[]/,$p'
}

# ─── Preconditions ────────────────────────────────────────────────────────────

if [ -z "${CXS_API_KEY:-}" ]; then
  err "api-key input is required"
  exit 1
fi

if [ -z "${INPUT_SITE:-}" ]; then
  err "site input is required"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  err "jq is required but was not found on the runner"
  exit 1
fi

DEV_FLAG=()
if is_true "${INPUT_CXS_DEV:-false}"; then
  DEV_FLAG=(--dev)
fi

# ─── Install the cxs CLI ──────────────────────────────────────────────────────

log "Installing cxs CLI"
export CXS_INSTALL_DIR="${CXS_INSTALL_DIR:-$HOME/.local/bin}"
curl -fsSL https://control.cdwcx.space/cxs/install.sh | bash

export PATH="$CXS_INSTALL_DIR:$PATH"
if [ -n "${GITHUB_PATH:-}" ]; then
  printf '%s\n' "$CXS_INSTALL_DIR" >>"$GITHUB_PATH"
fi

if ! command -v cxs >/dev/null 2>&1; then
  err "cxs CLI was not found on PATH after install"
  exit 1
fi

log "Using $(cxs --version)"

# ─── Verify auth ──────────────────────────────────────────────────────────────

if ! cxs "${DEV_FLAG[@]}" auth whoami --json >/dev/null 2>&1; then
  err "Authentication failed. Check that api-key is valid for the selected environment."
  exit 1
fi

# ─── Create site if needed ────────────────────────────────────────────────────

SELECTOR="$INPUT_SITE"

site_exists() {
  # Mirror the CLI selector logic: match on id, host, slug-username, or unique slug.
  cxs "${DEV_FLAG[@]}" site ls --json 2>/dev/null | extract_json | jq -e --arg sel "$SELECTOR" '
    [ .[]
      | (.host // "") as $host
      | ($host | sub("\\.(dev\\.)?cdwcx\\.space$"; "")) as $slugUser
      | select(.id == $sel or $host == $sel or $slugUser == $sel or .siteSlug == $sel)
    ] | length > 0
  ' >/dev/null
}

if is_true "${INPUT_CREATE:-true}"; then
  if site_exists; then
    log "Site '$SELECTOR' already exists; skipping create"
  else
    log "Creating site '$SELECTOR'"
    CREATE_FLAGS=()
    if ! is_true "${INPUT_INCLUDE_USERNAME:-true}"; then
      CREATE_FLAGS+=(--no-username)
    fi
    cxs "${DEV_FLAG[@]}" site create "$SELECTOR" "${CREATE_FLAGS[@]}" --json
  fi
fi

# ─── Deploy ───────────────────────────────────────────────────────────────────

log "Deploying '$INPUT_DIRECTORY' to '$SELECTOR'"
DEPLOY_OUT="$(cxs "${DEV_FLAG[@]}" deploy "$SELECTOR" "${INPUT_DIRECTORY:-.}" --json)"
printf '%s\n' "$DEPLOY_OUT"
DEPLOY_JSON="$(printf '%s\n' "$DEPLOY_OUT" | extract_json)"

HOST="$(printf '%s' "$DEPLOY_JSON" | jq -r '.host // empty')"
FILE_COUNT="$(printf '%s' "$DEPLOY_JSON" | jq -r '.fileCount // empty')"
DURATION_MS="$(printf '%s' "$DEPLOY_JSON" | jq -r '.durationMs // empty')"

if [ -z "$HOST" ]; then
  err "Deploy did not return a host"
  exit 1
fi

URL="https://$HOST"

# ─── Apply access policy (only when explicitly set) ───────────────────────────

if [ -n "${INPUT_ACCESS:-}" ]; then
  log "Applying access mode: $INPUT_ACCESS"
  ACCESS_FLAGS=()

  for domain in $(split_list "${INPUT_ACCESS_DOMAINS:-}"); do
    ACCESS_FLAGS+=(--domain "$domain")
  done
  for email in $(split_list "${INPUT_ACCESS_EMAILS:-}"); do
    ACCESS_FLAGS+=(--email "$email")
  done
  if [ -n "${INPUT_ACCESS_TIMEOUT:-}" ]; then
    ACCESS_FLAGS+=(--timeout "$INPUT_ACCESS_TIMEOUT")
  fi
  if [ -n "${INPUT_ACCESS_PASSWORD:-}" ]; then
    ACCESS_FLAGS+=(--password "$INPUT_ACCESS_PASSWORD")
  fi

  cxs "${DEV_FLAG[@]}" access "$SELECTOR" "$INPUT_ACCESS" "${ACCESS_FLAGS[@]}" --json
fi

# ─── Outputs ──────────────────────────────────────────────────────────────────

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    printf 'url=%s\n' "$URL"
    printf 'host=%s\n' "$HOST"
    printf 'file-count=%s\n' "$FILE_COUNT"
    printf 'duration-ms=%s\n' "$DURATION_MS"
  } >>"$GITHUB_OUTPUT"
fi

log "Deployed to $URL"
