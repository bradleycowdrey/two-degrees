#!/usr/bin/env bash
# Builds the docs/ folder that GitHub Pages serves, and that bradcowdrey.com/two-degrees shows:
#   docs/index.html  the product page (web/site.html), which embeds the app
#   docs/app.html    the app: web/app.html (the panel, written without <html>/<head> so it can also be
#                    published as a claude.ai Artifact) wrapped into a standalone page
set -euo pipefail
cd "$(dirname "$0")/.."
cp web/site.html docs/index.html
cp Resources/Cities.tsv docs/cities.tsv   # names "Use My Location" when Open-Meteo can't
{
  printf '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><link rel="icon" href="https://raw.githubusercontent.com/bradleycowdrey/two-degrees/main/docs/icon.png"></head><body>\n'
  cat web/app.html
  printf '\n</body></html>\n'
} > docs/app.html
echo "Built docs/index.html, docs/app.html and docs/cities.tsv"
