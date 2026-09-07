#!/usr/bin/env bash
# Shared helpers. Every script sources this one.
#
# Designed so the scripts behave identically inside GitHub Actions and on a
# developer machine: when the Actions variables are absent, the job summary
# goes to stdout and step outputs are discarded.

# Append a line to the job summary. Locally: prints to stdout.
summary() {
  printf '%s\n' "$*" >>"${GITHUB_STEP_SUMMARY:-/dev/stdout}"
}

# Publish a step output for later steps to consume.
set_output() {
  printf '%s=%s\n' "$1" "$2" >>"${GITHUB_OUTPUT:-/dev/null}"
}

# PR annotation, informational. Never fails the job on its own.
warn() {
  printf '::warning title=%s::%s\n' "$1" "$2"
}

# PR annotation, error level. Never exits on its own.
fail() {
  printf '::error title=%s::%s\n' "$1" "$2"
}

# Two-column table helpers, so no script hand-writes markdown pipes.
table_open() {
  summary ""
  summary "| | |"
  summary "|---|---|"
}

row() {
  summary "| $1 | $2 |"
}

# Abort with a clear message when a required variable is missing.
require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    fail "Missing configuration" "The action needs $name and it is empty."
    exit 1
  fi
}
