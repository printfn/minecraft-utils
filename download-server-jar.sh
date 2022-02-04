#!/usr/bin/env bash
set -euo pipefail

# Prerequisites:
#   * curl
#   * jq
#   * sha1sum (optional, skips hash verification if not installed)

# You can also run this script as:
# bash <(curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/printfn/minecraft-utils/main/download-server-jar.sh) latest

usage="Usage: download-server-jar.sh [flags] <version>

Downloads a specified Minecraft server.jar file

<version> can be a version number like '1.18.1', or it can be 'latest',
    'latest-snapshot', 'list', 'list-latest' or 'list-latest-snapshot'

Flags:
    --curl-flag <flag>  passes the specified flag through to \`curl\`
-h  --help              show this help screen
-q  --quiet             suppress output
-v  --verbose           show more detailed output"

quiet=false
verbose=false
foundcmd=false
curlflags=""

while [[ "$#" != 0 ]]; do
    arg="$1"
    if [[ "$arg" == "-q" || "$arg" == "--quiet" ]]; then
        quiet=true
    elif [[ "$arg" == "-v" || "$arg" == "--verbose" ]]; then
        verbose=true
    elif [[ "$arg" == "--curl-flag" ]]; then
        shift
        if [[ "$#" == 0 ]]; then
            echo "error: expected a curl flag" >&2
            exit 1
        fi
        curlflags="$curlflags $1"
    elif [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        echo "$usage"
        exit
    elif [[ "$arg" =~ ^- ]]; then
        echo "error: unknown option '$arg'" >&2
        exit 1
    elif [[ "$foundcmd" == false ]]; then
        command="$arg"
        foundcmd=true
    else
        echo "error: too many arguments" >&2
        exit 1
    fi
    shift
done

if [[ "$foundcmd" == false ]]; then
    echo "$usage" >&2
    exit 1
fi

if [[ "$verbose" == true ]]; then
    echo "Downloading version manifest from https://launchermeta.mojang.com/mc/game/version_manifest.json..."
fi
data=$(curl -sS $curlflags https://launchermeta.mojang.com/mc/game/version_manifest.json)

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

if [[ "$verbose" == true ]]; then
    echo "Found version $version"
elif [[ "$quiet" != true ]]; then
    echo "Downloading version $version..."
fi

url=$(echo "$data" | jq -r ".versions[] | select(.id == \"$version\") | .url")
if [[ -z "$url" ]]; then
    echo "error: unknown version '$version'" >&2
    exit 1
fi

if [[ "$verbose" == true ]]; then
    echo "Downloading version info from $url..."
fi

data=$(curl -Ss $curlflags "$url" | jq .downloads.server)
url=$(echo "$data" | jq -r .url)

if [[ "$verbose" == true ]]; then
    echo "Downloading server.jar from $url..."
fi

sha1=$(echo "$data" | jq -r .sha1)

curlsilent=""
if [[ "$quiet" == true ]]; then
    curlsilent="--silent"
fi

curl $curlsilent $curlflags -# -o server.jar "$url"

if command -v sha1sum &>/dev/null; then
    if ! sha1sum --check --strict --status <(echo "$sha1 server.jar"); then
        echo "error: checksum mismatch" >&2
        exit 1
    fi
elif command -v shasum &>/dev/null; then
    # two spaces are necessary, otherwise `shasum` returns an error`
    if ! shasum --algorithm 1 --check --strict --status <(echo "$sha1  server.jar"); then
        echo "error: checksum mismatch" >&2
        exit 1
    fi
else
    # skip verification
    echo "warning: neither \`sha1sum\` or \`shasum\` is installed: skipping hash verification" >&2
    exit
fi
