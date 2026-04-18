#!/bin/sh
set -e
# Run migrations
echo "Running database migrations..."
mix ecto.migrate

# Backfill missing duration_ms values (idempotent; only NULL rows are processed)
if [ "${BACKFILL_DURATIONS_ON_BOOT:-true}" = "true" ]; then
  echo "Backfilling clip durations..."

  if [ "${BACKFILL_DURATIONS_INCLUDE_URL:-false}" = "true" ]; then
    mix soundboard.backfill_durations --include-url
  else
    mix soundboard.backfill_durations
  fi
fi

# Start Phoenix server in foreground
# Using exec ensures proper signal handling and process management
echo "Starting Phoenix server..."
exec mix phx.server
