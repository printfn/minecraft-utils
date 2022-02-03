#!/usr/bin/env bash
set -euo pipefail

# Prerequisites:
#   * curl
#   * jq
#   * sha1sum (optional, skips hash verification if not installed)

# You can also run this script as:
# bash <(curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/printfn/minecraft-utils/main/download-server-jar.sh) latest

if [[ "$#" == 0 ]]; then
  echo "Usage: $0 <version> (or one of 'latest', 'latest-snapshot', 'list', 'list-latest', 'list-latest-snapshot')" >&2
  exit 1
fi

data=$(curl -sS https://launchermeta.mojang.com/mc/game/version_manifest.json)

if [[ "$1" == "latest" ]]; then
    version=$(echo "$data" | jq -r .latest.release)
elif [[ "$1" == "list-latest" ]]; then
    echo "$data" | jq -r ".latest.release"
    exit
elif [[ "$1" == "latest-snapshot" ]]; then
    version=$(echo "$data" | jq -r .latest.snapshot)
elif [[ "$1" == "list-latest-snapshot" ]]; then
    echo "$data" | jq -r ".latest.snapshot"
    exit
elif [[ "$1" == "list" ]]; then
    echo "$data" | jq -r ".versions[].id"
    exit
else
    version="$1"
fi

echo "Downloading version $version..."

url=$(echo "$data" | jq -r ".versions[] | select(.id == \"$version\") | .url")
if [[ -z "$url" ]]; then
    echo "Unknown version '$version'"
    exit 1
fi
data=$(curl -Ss "$url" | jq .downloads.server)
url=$(echo "$data" | jq -r .url)
sha1=$(echo "$data" | jq -r .sha1)
curl -o server.jar "$url"

if ! command -v sha1sum &>/dev/null; then
    # sha1sum not installed, skip verification
    exit
fi
if ! sha1sum --check <(echo "$sha1 server.jar") &>/dev/null; then
    echo "Error: checksum mismatch" >&2
    exit 1
fi
