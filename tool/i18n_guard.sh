#!/usr/bin/env bash
#
# i18n guard: fails if a likely hardcoded user-facing English string appears in
# lib/ outside the localization layer. Meant for CI, so translations don't
# silently regress. This is a heuristic, not a proof: it matches common widget
# literals (Text/Tab/tooltip/labelText/hintText/helperText) and filters out an
# allowlist of brands, technical tokens, and example URLs.
#
# If it flags a legitimate literal (a brand name, a code token, an example),
# add the term to ALLOW below. If it flags real UI copy, localize it via
# AppLocalizations (see lib/l10n/app_en.arb and CONTRIBUTING notes).
set -euo pipefail
cd "$(dirname "$0")/.."

# Widget constructors/params whose string literal is shown to users.
PATTERN="(Text\(|Tab\(text: |tooltip: |labelText: |hintText: |helperText: |SnackBar\(content: Text\()'[A-Za-z][^']*'"

# Brands, proper nouns, technical tokens, and example placeholders that are
# intentionally never translated.
ALLOW='Fathom|Seerr|Sonarr|Radarr|Arr|Jellyseerr|YouTube|Jellyfin|IMDb|TMDB|MDBList|LrcLib|SponsorBlock|DeArrow|Return YouTube Dislike|Rotten Tomatoes|Letterboxd|Metacritic|Trakt|trakt|MyAnimeList|MAL|Ko-fi|HDHomeRun|XMLTV|Schedules Direct|VAAPI|NVENC|QSV|QuickSync|VideoToolbox|AMF|Rockchip|V4L2|HEVC|AV1|UPnP|IPv6|DLNA|FFmpeg|https?://|www\.|\.com|\.xml|\.json|e\.g\.|v\$\{|'"'"'[A-Z]'"'"'|^.{0,40}(MP4|MKV|M4A|MP3|Mbps|kbps|1080p|2160p|4K)'

# Collect matched literals (file:line:literal), drop the l10n layer, tests, and
# generated code, then filter the allowlist.
matches=$(grep -rnoE "$PATTERN" lib --include='*.dart' 2>/dev/null \
  | grep -vE '/l10n/|generated/|_test\.dart' \
  | grep -vE "$ALLOW" || true)

if [ -n "$matches" ]; then
  echo "i18n guard FAILED: hardcoded user-facing strings found."
  echo "Localize them via AppLocalizations, or add brands/tokens to ALLOW in tool/i18n_guard.sh:"
  echo
  echo "$matches"
  exit 1
fi

echo "i18n guard: OK (no hardcoded UI strings)."
