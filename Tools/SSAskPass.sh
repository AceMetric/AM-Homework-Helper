#!/bin/sh
# Git's useHttpPath prompt must name the approved repository before any secret is returned.
[ -n "$SS_GIT_REPOSITORY" ] || exit 1
prompt=$(printf '%s' "$1" | /usr/bin/tr '[:upper:]' '[:lower:]')
case "$prompt" in
  *"$SS_GIT_REPOSITORY.git"*) ;;
  *) exit 1 ;;
esac
case "$1" in
  *Username*|*username*) printf '%s\n' 'x-access-token' ;;
  *Password*|*password*) printf '%s\n' "$SS_GIT_TOKEN" ;;
  *) exit 1 ;;
esac
