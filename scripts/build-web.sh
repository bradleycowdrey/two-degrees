#!/usr/bin/env bash
# Wraps docs/app.html (the panel, written without <html>/<head> so it can also be published
# as a claude.ai Artifact) into the standalone docs/index.html served by GitHub Pages.
set -euo pipefail
cd "$(dirname "$0")/.."
{
  printf '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><link rel="icon" href="icon.png"></head><body>\n'
  cat docs/app.html
  printf '\n</body></html>\n'
} > docs/index.html
echo "Built docs/index.html"
