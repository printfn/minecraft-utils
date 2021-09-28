#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" == 0 ]]; then
  echo "Usage: $0 <version> (or one of 'latest', 'latest-snapshot', 'list')" >&2
  exit 1
fi

data=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json)

if [[ "$1" == "latest" ]]; then
    version=$(echo "$data" | jq -r .latest.release)
elif [[ "$1" == "latest-snapshot" ]]; then
    version=$(echo "$data" | jq -r .latest.snapshot)
elif [[ "$1" == "list" ]]; then
    echo "$data" | jq -r ".versions[].id"
    exit
else
    version="$1"
fi

echo "Downloading version $version..."

url=$(echo "$data" | jq -r ".versions[] | select(.id == \"$version\") | .url")
data=$(curl -s $url | jq .downloads.server)
url=$(echo "$data" | jq -r .url)
sha1=$(echo "$data" | jq -r .sha1)
curl -o server.jar $url
sha1sum --check <(echo "$sha1 server.jar") >/dev/null 2>/dev/null
if [[ $? != 0 ]]; then
    echo "Error: checksum mismatch" >&2
    exit 1
fi
