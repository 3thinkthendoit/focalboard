#!/bin/sh
set -e

CONFIG=/opt/focalboard/config.json
SERVER=/opt/focalboard/bin/focalboard-server

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

apply_json port "$FB_PORT"
apply_json dbtype "$FB_DB_TYPE"
apply_json dbconfig "$FB_DB_CONFIG"
apply_json useSSL "$FB_USE_SSL"
apply_json secureCookie "$FB_SECURE_COOKIES"

# focalboard-server requires FOCALBOARD_SINGLE_USER_TOKEN when --single-user
# is set. Treat FB_SINGLE_USER_TOKEN as that source (generate one if absent).
if [ -z "$FB_SINGLE_USER_TOKEN" ]; then
  FB_SINGLE_USER_TOKEN=$(head -c 16 /dev/urandom | sha256sum | cut -c1-32)
fi
export FOCALBOARD_SINGLE_USER_TOKEN="$FB_SINGLE_USER_TOKEN"

# Build the server command. --dbconfig is only passed when set.
set -- "$SERVER" --port "$FB_PORT" --single-user --dbtype "$FB_DB_TYPE"
if [ -n "$FB_DB_CONFIG" ]; then
  set -- "$@" --dbconfig "$FB_DB_CONFIG"
fi

exec "$@"
