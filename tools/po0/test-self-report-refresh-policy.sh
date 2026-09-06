#!/usr/bin/env bash
set -euo pipefail
# Refresh, stale paths, failure reporting and legacy migration now use the
# independent-channel scheduler fixtures, also covering pause and deletion.
bash "$(cd "$(dirname "$0")" && pwd -P)/test-client-channel-schedules.sh"
