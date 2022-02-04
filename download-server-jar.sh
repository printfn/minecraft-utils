#!/usr/bin/env bash
set -euo pipefail

# Prerequisites:
#   * curl
#   * jq
#   * sha1sum (optional, skips hash verification if not installed)

# You can also run this script as:
# bash <(curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/printfn/minecraft-utils/main/download-server-jar.sh) latest

usage="Usage: $0 [-q|--quiet] <version> (or one of 'latest', 'latest-snapshot', 'list', 'list-latest', 'list-latest-snapshot')"

quiet=false
foundcmd=false

while [[ "$#" != 0 ]]; do
    arg="$1"
    if [[ "$arg" == "-q" || "$arg" == "--quiet" ]]; then
        quiet=true
    elif [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        echo "$usage"
        exit
    elif [[ "$arg" =~ ^- ]]; then
        echo "Unknown option '$arg'" >&2
        exit 1
    elif [[ "$foundcmd" == false ]]; then
        command="$arg"
        foundcmd=true
    else
        echo "Too many arguments" >&2
        exit 1
    fi
    shift
done

if [[ "$foundcmd" == false ]]; then
    echo "$usage" >&2
    exit 1
fi

data=$(curl -sS https://launchermeta.mojang.com/mc/game/version_manifest.json)

if [[ "$command" == "latest" ]]; then
    version=$(echo "$data" | jq -r .latest.release)
elif [[ "$command" == "list-latest" ]]; then
    echo "$data" | jq -r ".latest.release"
    exit
elif [[ "$command" == "latest-snapshot" ]]; then
    version=$(echo "$data" | jq -r .latest.snapshot)
elif [[ "$command" == "list-latest-snapshot" ]]; then
    echo "$data" | jq -r ".latest.snapshot"
    exit
elif [[ "$command" == "list" ]]; then
    echo "$data" | jq -r ".versions[].id"
    exit
else
    version="$command"
fi

if [[ "$quiet" != true ]]; then
    echo "Downloading version $version..."
fi

url=$(echo "$data" | jq -r ".versions[] | select(.id == \"$version\") | .url")
if [[ -z "$url" ]]; then
    echo "Unknown version '$version'"
    exit 1
fi
data=$(curl -Ss "$url" | jq .downloads.server)
url=$(echo "$data" | jq -r .url)
sha1=$(echo "$data" | jq -r .sha1)

curlsilent=""
if [[ "$quiet" == true ]]; then
    curlsilent="--silent"
fi

curl $curlsilent -o server.jar "$url"

if ! command -v sha1sum &>/dev/null; then
    # sha1sum not installed, skip verification
    exit
fi
if ! sha1sum --check <(echo "$sha1 server.jar") &>/dev/null; then
    echo "Error: checksum mismatch" >&2
    exit 1
fi
