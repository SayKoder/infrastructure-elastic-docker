#!/bin/bash
set -e
update-ca-certificates 2>/dev/null || true
exec docker-entrypoint.sh apache2-foreground
