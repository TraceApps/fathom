#!/usr/bin/env bash
# Starts a real Jellyfin server with one short movie and a subtitle beside
# it, for test/server/jellyfin_flows_test.dart. CI runs this against an old
# server and the current one; it works the same on a developer's machine.
#
#   tool/server_test_setup.sh [image]      start (default jellyfin/jellyfin:latest)
#   tool/server_test_setup.sh stop         stop and remove it
#
# Prints the environment the test reads.
set -euo pipefail

NAME=fathom-server-test
PORT="${FATHOM_SERVER_TEST_PORT:-18196}"
URL="http://127.0.0.1:$PORT"
USERNAME=tester
PASSWORD=fathom-test

if [ "${1:-}" = stop ]; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  exit 0
fi
IMAGE="${1:-jellyfin/jellyfin:latest}"

WORK="$(mktemp -d)"
MOVIE="$WORK/media/Fathom Test Movie (2020)"
mkdir -p "$MOVIE"
# Ten minutes: Jellyfin keeps no resume point for anything under five.
# Tiny all the same: a still color.
# Made with the ffmpeg inside the Jellyfin image itself, so nothing has to
# be installed to run this.
chmod -R a+rwX "$WORK"
docker run --rm --user "$(id -u):$(id -g)" --entrypoint /usr/lib/jellyfin-ffmpeg/ffmpeg \
  -v "$MOVIE:/out" "$IMAGE" -loglevel error -y \
  -f lavfi -i "color=c=navy:s=320x180:r=5:d=600" \
  -f lavfi -i "anullsrc=r=22050:cl=mono" -shortest \
  -c:v libx264 -preset ultrafast -crf 40 -c:a aac -b:a 16k \
  "/out/Fathom Test Movie (2020).mkv"
cat > "$MOVIE/Fathom Test Movie (2020).en.srt" <<'SRT'
1
00:00:01,000 --> 00:00:04,000
A line of the test subtitle.
SRT
chmod -R a+rX "$WORK"

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p "127.0.0.1:$PORT:8096" \
  -v "$WORK/media:/media:ro" "$IMAGE" >/dev/null

# Jellyfin 12 answers from a small startup server first, then drops the port
# for a moment while the real one takes over: wait until it has answered
# three times running.
steady=0
for _ in $(seq 1 120); do
  if curl -sf "$URL/System/Info/Public" >/dev/null; then
    steady=$((steady + 1))
    [ "$steady" -ge 3 ] && break
  else
    steady=0
  fi
  sleep 2
done
[ "$steady" -ge 3 ] || {
  echo "Jellyfin did not start" >&2
  docker logs --tail 40 "$NAME" >&2
  exit 1
}

json=(-H 'Content-Type: application/json')
# A new server answers before it's done setting itself up (12 migrates its
# database first): wait until the wizard itself answers.
for _ in $(seq 1 60); do
  curl -sf "$URL/Startup/Configuration" >/dev/null && break
  sleep 2
done
# The first-run wizard, as the web client walks it.
curl -sf -X POST "${json[@]}" "$URL/Startup/Configuration" \
  -d '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}' >/dev/null
curl -sf "$URL/Startup/User" >/dev/null
curl -sf -X POST "${json[@]}" "$URL/Startup/User" \
  -d "{\"Name\":\"$USERNAME\",\"Password\":\"$PASSWORD\"}" >/dev/null
curl -sf -X POST "${json[@]}" "$URL/Startup/RemoteAccess" \
  -d '{"EnableRemoteAccess":true,"EnableAutomaticPortMapping":false}' >/dev/null
curl -sf -X POST "$URL/Startup/Complete" >/dev/null

AUTH='MediaBrowser Client="fathom-test", Device="ci", DeviceId="fathom-ci", Version="1"'
TOKEN=$(curl -sf -X POST "${json[@]}" -H "Authorization: $AUTH" \
  "$URL/Users/AuthenticateByName" \
  -d "{\"Username\":\"$USERNAME\",\"Pw\":\"$PASSWORD\"}" |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["AccessToken"])')

# No metadata fetchers: the test must not depend on the internet.
curl -sf -X POST "${json[@]}" -H "Authorization: MediaBrowser Token=\"$TOKEN\"" \
  "$URL/Library/VirtualFolders?name=Movies&collectionType=movies&paths=%2Fmedia&refreshLibrary=true" \
  -d '{"LibraryOptions":{"EnableInternetProviders":false,"MetadataSavers":[],"TypeOptions":[]}}' >/dev/null

found=0
for i in $(seq 1 90); do
  # A scan asked for while the server is still settling can be dropped: ask
  # again now and then.
  if [ $((i % 10)) -eq 0 ]; then
    curl -sf -X POST -H "Authorization: MediaBrowser Token=\"$TOKEN\"" "$URL/Library/Refresh" >/dev/null || true
  fi
  found=$(curl -sf -H "Authorization: MediaBrowser Token=\"$TOKEN\"" \
    "$URL/Items?Recursive=true&IncludeItemTypes=Movie&Limit=0" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["TotalRecordCount"])')
  [ "$found" -ge 1 ] && break
  sleep 2
done
[ "$found" -ge 1 ] || { echo "The library never showed the movie" >&2; exit 1; }

# The movie is listed before the scan has finished placing it in its
# library: wait for the scan itself.
for _ in $(seq 1 60); do
  state=$(curl -sf -H "Authorization: MediaBrowser Token=\"$TOKEN\"" "$URL/ScheduledTasks" |
    python3 -c 'import json,sys; print(next((t["State"] for t in json.load(sys.stdin) if t.get("Key")=="RefreshLibrary"), "Idle"))')
  [ "$state" = Idle ] && break
  sleep 2
done

echo "FATHOM_JELLYFIN_URL=$URL"
echo "FATHOM_JELLYFIN_USER=$USERNAME"
echo "FATHOM_JELLYFIN_PASSWORD=$PASSWORD"
