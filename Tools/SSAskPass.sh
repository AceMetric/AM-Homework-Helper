#!/bin/sh
case "$1" in
  *Username*|*username*) printf '%s\n' 'x-access-token' ;;
  *Password*|*password*) printf '%s\n' "$SS_GIT_TOKEN" ;;
  *) exit 1 ;;
esac
