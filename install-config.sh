#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$ROOT_DIR/scripts/config-generate.sh"
"$ROOT_DIR/scripts/config-update.sh"
