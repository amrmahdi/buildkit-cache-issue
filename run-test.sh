#!/bin/bash
set -e

function cleanup {
    if [[ -n "$BUILDKITD_PID" ]]; then
        echo "Stopping buildkitd"
        kill "$BUILDKITD_PID"
    fi
    if [[ -n "$CONTAINERD_PID" ]]; then
        echo "Stopping containerd"
        kill "$CONTAINERD_PID"
    fi

    stop_registry
}

function pruneEverything {
    echo "Pruning everything"
    buildctl prune --all
    ctr -n buildkit images rm $(ctr -n buildkit images ls -q)
    ctr -n buildkit content rm $(ctr -n buildkit content ls -q)
}

start_registry() {
  echo "Start local registry for caching"
  registry_cache=$(docker run -d -p 5000:5000 --restart=always --name registry registry:2)
}

stop_registry() {
  if [ -n "$registry_cache" ]
  then
    echo "Stop local registry for caching"
    docker rm -vf $registry_cache
  fi
}

command -v containerd >/dev/null && echo "containerd found..." || { echo "containerd not installed."; exit 1; }
command -v buildkitd >/dev/null && echo "buildkitd found..." || { echo "buildkitd not installed."; exit 1; }
command -v buildctl >/dev/null && echo "buildctl found..." || { echo "buildctl not installed."; exit 1; }

trap cleanup EXIT
echo "Starting containerd"
containerd &
CONTAINERD_PID=$!
echo "Starting buildkitd"
buildkitd --config ./config.toml &
BUILDKITD_PID=$!

sleep 10

pruneEverything

start_registry

echo "Building and exporting parent image"
pushd .
cd simple
buildctl build . --frontend dockerfile.v0 --local context=. --local dockerfile=. --output type=image,oci-mediatypes=true,name=amr.cr/foo:bar --export-cache=type=registry,ref=localhost:5000/cache/simple:0
popd
echo "Building and exporting child image"
pushd .
cd simple-child
buildctl build . --frontend dockerfile.v0 --local context=. --local dockerfile=. --output type=image,oci-mediatypes=true,name=amr.cr/foochild:bar --export-cache=type=registry,name=localhost:5000/cache/simplechild:0
popd

ctr -n buildkit images ls

pruneEverything

echo "Building (with import-from) parent image"
pushd .
cd simple
buildctl build . --frontend dockerfile.v0 --local context=. --local dockerfile=. --output type=image,oci-mediatypes=true,name=amr.cr/foo:bar --import-cache=type=registry,ref=localhost:5000/cache/simple:0
popd
echo "Building (with import-from) child image"
pushd .
cd simple-child
buildctl build . --frontend dockerfile.v0 --local context=. --local dockerfile=. --output type=image,oci-mediatypes=true,name=amr.cr/foochild:bar --import-cache=type=registry,name=localhost:5000/cache/simplechild:0
popd

ctr -n buildkit images ls