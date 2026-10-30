#!/usr/bin/env bash
# Build the landing page into public/ — screenshots, live versions, template.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p public/assets

# curl wrapper: auth only when GITHUB_TOKEN present (empty header breaks auth-less
# calls), retries on transient TLS/CDN hiccups.
ghcurl() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL --connect-timeout 15 --max-time 90 --retry 2 -H "Authorization: Bearer $GITHUB_TOKEN" "$@"
  else
    curl -fsSL --connect-timeout 15 --max-time 90 --retry 2 "$@"
  fi
}

# --- screenshots (same-origin copies) ----------------------------------------
fetch_asset() {
  ghcurl -o "public/$2" "$1"
  echo "asset $2"
}
fetch_asset "https://raw.githubusercontent.com/bd-loser/opencode-bionic/main/docs/assets/tui-welcome.png" assets/tui-welcome.png
fetch_asset "https://raw.githubusercontent.com/bd-loser/opencode-bionic/main/docs/assets/tui-models.png" assets/tui-models.png

# --- badges (built at build-time so the page has zero third-party requests) --
badge() { # value-with-color file
  ghcurl -o "public/assets/$2.svg" "https://img.shields.io/badge/$1"
  head -c 4 <"public/assets/$2.svg" | grep -q "<svg" || { echo "badge $2 is not SVG (upstream failure)" >&2; exit 1; }
  echo "badge $2"
}

# --- robots + sitemap ---------------------------------------------------------
cp robots.txt public/

# --- live versions from tags + releases API, committed fallback ---------------
PY_TAGS="$(python3 - <<'EOF'
import json, os, re, subprocess
names = []
for page in range(1, 6):
    raw = subprocess.run(
        (["curl", "-fsSL", "--retry", "2", "-H", f"Authorization: Bearer {os.environ['GITHUB_TOKEN']}"]
          if os.environ.get("GITHUB_TOKEN") else ["curl", "-fsSL", "--retry", "2"]) +
        [f"https://api.github.com/repos/bd-loser/opencode-bionic/tags?per_page=100&page={page}"],
        capture_output=True, text=True, timeout=90)
    if raw.returncode:
        break
    names += [t["name"] for t in json.loads(raw.stdout)]
if not names:
    raise SystemExit(1)
def pick(pat):
    v = sorted((n for n in names if re.fullmatch(pat, n)), key=lambda n: [int(x) for x in re.findall(r"\d+", n)])
    return (v[-1][1:] if v else "")
print(pick(r"v1\.[0-9]+\.[0-9]+-v1\.[0-9a-f]{8}"))
print(pick(r"v[0-9]+\.[0-9]+\.[0-9]+"))
print(pick(r"v[0-9.]+-dev\.[0-9a-f]{8}"))
EOF
)" || PY_TAGS=""

V_BUN="$(ghcurl "https://api.github.com/repos/bd-loser/bun-termux/releases/latest" \
  | python3 -c 'import json,sys; t=json.load(sys.stdin).get("tag_name",""); print(t[1:] if t.startswith("v") else t)')" \
  || V_BUN=""

# shellcheck disable=SC1091
[ -f versions.env ] && . ./versions.env

SANITY=$([ -n "$PY_TAGS" ] && echo 1 || echo 0)
V_STABLE="$(echo "$PY_TAGS" | sed -n 2p)"
V_V1="$(echo "$PY_TAGS" | sed -n 1p)"

: "${V_STABLE:=$FALLBACK_STABLE}"
: "${V_V1:=$FALLBACK_V1}"
V_DEV="$(echo "$PY_TAGS" | sed -n 3p)";     : "${V_DEV:=$FALLBACK_DEV}"
: "${V_BUN:=$FALLBACK_BUN}"

echo "versions: stable=$V_STABLE v1=$V_V1 dev=$V_DEV bun=$V_BUN (api=$SANITY)"
BUILD_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- sitemap with fresh lastmod ------------------------------------------------
sed "s|<url><loc>https://bd-loser.github.io/</loc></url>|<url><loc>https://bd-loser.github.io/</loc><lastmod>${BUILD_TS}</lastmod></url>|" sitemap.xml > public/sitemap.xml

# --- badges once versions are known -------------------------------------------
badge "stable-${V_STABLE}-blue" badge-stable
badge "v1-${V_V1//-/--}-a855f7" badge-v1
badge "dev-${V_DEV//-/--}-purple" badge-dev
badge "bun.termux-${V_BUN//-/--}-green" badge-bun

# --- inject into template ------------------------------------------------------
python3 - "$V_STABLE" "$V_V1" "$V_DEV" "$V_BUN" "$BUILD_TS" <<'EOF'
import sys
tokens = dict(zip(("__V_STABLE__", "__V_V1__", "__V_DEV__", "__V_BUN__", "__BUILD_TS__"), sys.argv[1:6]))
src = open("src/index.template.html").read()
for k, v in tokens.items():
    if v == "":
        raise SystemExit(f"missing version for {k}")
    src = src.replace(k, v)
open("public/index.html", "w").write(src)
print("public/index.html assembled")
EOF
