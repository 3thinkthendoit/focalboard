#!/bin/sh
set -e

CONFIG=/opt/focalboard/config.json
SERVER=/opt/focalboard/bin/focalboard-server

# Defaults for tunable env vars (override via docker -e / compose environment:).
: "${FB_PORT:=8000}"
: "${FB_DB_TYPE:=sqlite3}"
: "${FB_DB_CONFIG:=}"
: "${FB_USE_SSL:=false}"
: "${FB_SECURE_COOKIES:=false}"
# Single-user mode by default (no login/register). Set FB_SINGLE_USER=false to
# enable multi-user registration.
: "${FB_SINGLE_USER:=true}"
# Public base URL used to build registration/team links. Must match the URL
# users actually visit (e.g. https://your-domain.com).
: "${FB_SERVER_ROOT:=}"

# Use jq (installed in the image) to safely override config.json values.
apply_json() {
  key="$1"
  val="$2"
  if [ -n "$val" ]; then
    tmp=$(mktemp)
    jq --arg k "$key" --arg v "$val" '.[$k] = $v' "$CONFIG" > "$tmp"
    mv "$tmp" "$CONFIG"
  fi
}

# focalboard reads FOCALBOARD_* env vars via viper.AutomaticEnv(), which
# override config.json (env > file). We expose FB_PORT as the user-facing knob
# and make it the highest-priority source: if FB_PORT is set we force
# FOCALBOARD_PORT to match it, so a user-provided FOCALBOARD_PORT (or any other
# source) cannot override the intended port.
#
# Also guard against a malformed value like "tcp://host:8080" (e.g. someone
# pasted a docker link var). Extract the trailing port number if present.
clean_port() {
  p="$1"
  # case tcp://10.0.0.1:8080 or 10.0.0.1:8080 -> 8080
  case "$p" in
    *:*) p="${p##*:}" ;;
  esac
  # strip anything non-digit
  p=$(printf '%s' "$p" | tr -cd '0-9')
  printf '%s' "$p"
}

# FB_PORT is the user-facing knob. If unset we fall back to the default 8000
# already applied above. Sanitize both FB_PORT and any user-provided
# FOCALBOARD_PORT (viper reads FOCALBOARD_* and would otherwise crash on a
# malformed "tcp://host:port" value).
if [ -n "$FOCALBOARD_PORT" ]; then
  FOCALBOARD_PORT=$(clean_port "$FOCALBOARD_PORT")
fi
if [ -n "$FB_PORT" ]; then
  FB_PORT=$(clean_port "$FB_PORT")
fi
# If either produced an empty/invalid port, fall back to the default.
if [ -z "$FB_PORT" ]; then
  FB_PORT=8000
fi
# FB_PORT wins: force FOCALBOARD_PORT to match so viper uses the same value.
export FOCALBOARD_PORT="$FB_PORT"

apply_json port "$FB_PORT"
apply_json dbtype "$FB_DB_TYPE"
apply_json dbconfig "$FB_DB_CONFIG"
apply_json useSSL "$FB_USE_SSL"
apply_json secureCookie "$FB_SECURE_COOKIES"

# serverRoot drives registration/team invite links. Derive a default from the
# port when not provided so generated links use the right host.
if [ -n "$FB_SERVER_ROOT" ]; then
  apply_json serverRoot "$FB_SERVER_ROOT"
elif [ "$FB_SINGLE_USER" = "false" ]; then
  apply_json serverRoot "http://localhost:${FB_PORT}"
fi

# focalboard-server requires FOCALBOARD_SINGLE_USER_TOKEN when --single-user
# is set. Treat FB_SINGLE_USER_TOKEN as that source (generate one if absent).
if [ -z "$FB_SINGLE_USER_TOKEN" ]; then
  FB_SINGLE_USER_TOKEN=$(head -c 16 /dev/urandom | sha256sum | cut -c1-32)
fi
export FOCALBOARD_SINGLE_USER_TOKEN="$FB_SINGLE_USER_TOKEN"

# Build the server command. --dbconfig is only passed when set.
set -- "$SERVER" --config /opt/focalboard/config.json --port "$FB_PORT" --dbtype "$FB_DB_TYPE"
if [ "$FB_SINGLE_USER" != "false" ]; then
  set -- "$@" --single-user
fi
if [ -n "$FB_DB_CONFIG" ]; then
  set -- "$@" --dbconfig "$FB_DB_CONFIG"
fi

exec "$@"
