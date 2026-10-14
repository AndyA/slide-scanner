#!/bin/bash

set -e

prefix="https://github.com/ZigEmbeddedGroup/microzig/releases/download"
state="tmp/matrix"
mkdir -p "$state"

for minor in {17..2}; do
  version="0.17.$minor"
  for zig in "master" "0.17.0" "0.17.0-dev.1936+5a625d5f3"; do
    zvm use "$zig" > /dev/null
    zig_version="$( zig version )"
    tag="$state/$version-$zig_version.seen"
    if [[ -e $tag ]]; then
      echo "Skipping microzig $version with zig $zig_version"
      continue
    fi
    touch "$tag"
    echo "Trying microzig $version with zig $zig_version"
    rm -rf .zig-cache .zig-*
    zig fetch --save "$prefix/$version/microzig.tar.gz"
    if zig build; then
      echo "$zig_version" > .zigversion
      echo "Build OK with microzig $version, zig $zig_version; stopping"
      exit 0
    fi
  done
done

echo "No dice"
exit 1