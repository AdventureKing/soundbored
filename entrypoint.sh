#!/bin/sh
set -e
# Run migrations
echo "Running database migrations..."
if ! mix ecto.migrate; then
  echo "WARNING: Database migrations failed; continuing startup anyway."
fi

# Start Phoenix server in foreground
# Using exec ensures proper signal handling and process management
echo "Starting Phoenix server..."
exec mix phx.server
