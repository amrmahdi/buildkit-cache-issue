#!/bin/bash
set -e

IMAGE=moby/buildkit:master-rootless

title() {
  echo $'=== \e[1m'$@$'\e[0m'
}

error() {
  echo $'\e[1;31m'$@$'\e[0m'
}

success() {
  echo $'\e[1;32m'$@$'\e[0m'
}

start_registry() {
    title "Start local registry for caching"
    registry_cache=$(docker run -p 5000:5000 -d registry:2)
}

stop_registry() {
  if [ -n "$registry_cache" ]
  then
    title "Stop local registry for caching"
    docker rm -vf $registry_cache
  fi
}

buildctl-daemonless() {
    links="$links --link $registry_cache:registry-cache"
    docker run \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    -v $(pwd)/context:/context \
    -v $(pwd)/config.toml:/etc/buildkit/buildkitd.toml \
    -e BUILDKITD_FLAGS='--oci-worker-no-process-sandbox --config /etc/buildkit/buildkitd.toml' \
    --rm \
    -ti \
    --entrypoint buildctl-daemonless.sh \
    $links \
    ${IMAGE} \
    "$@"
}

function cleanup {
    removeImages
    stop_registry
}

removeImages() {
    title "Removing images from docker daemon"
    docker rmi $(docker images localhost:5000/* -a -q)
}

trap cleanup EXIT

start_registry

title "Building and exporting parent image"
buildctl-daemonless build . --frontend dockerfile.v0 --local context=/context/simple --local dockerfile=/context/simple --output type=image,oci-mediatypes=true,name=registry-cache:5000/foo:bar,push=true --export-cache=type=registry,ref=registry-cache:5000/cache/simple:0

title "Building and exporting child image"
buildctl-daemonless build . --frontend dockerfile.v0 --local context=/context/simple-child --local dockerfile=/context/simple-child --output type=image,oci-mediatypes=true,name=registry-cache:5000/foochild:bar,push=true --export-cache=type=registry,name=registry-cache:5000/cache/simplechild:0

title "Pulling images to docker daemon for inspection"
docker pull localhost:5000/foo:bar
docker pull localhost:5000/foochild:bar
docker images localhost:5000/*

original_foo_id=$(docker images localhost:5000/foo:bar -q)
original_foochild_id=$(docker images localhost:5000/foochild:bar -q)

removeImages

title "Building (with import-from) parent image"
buildctl-daemonless build . --frontend dockerfile.v0 --local context=/context/simple --local dockerfile=/context/simple --output type=image,oci-mediatypes=true,name=registry-cache:5000/foo:bar,push=true --import-cache=type=registry,ref=registry-cache:5000/cache/simple:0

title "Building (with import-from) child image"
buildctl-daemonless build . --frontend dockerfile.v0 --local context=/context/simple-child --local dockerfile=/context/simple-child --output type=image,oci-mediatypes=true,name=registry-cache:5000/foochild:bar,push=true --import-cache=type=registry,name=registry-cache:5000/cache/simplechild:0

title "Pulling images to docker daemon for inspection"
docker pull localhost:5000/foo:bar
docker pull localhost:5000/foochild:bar
docker images localhost:5000/*

rebuild_original_foo_id=$(docker images localhost:5000/foo:bar -q)
rebuild_original_foochild_id=$(docker images localhost:5000/foochild:bar -q)

# Check if the images are the same
if [ "$original_foo_id" != "$rebuild_original_foo_id" ]
then
  error "Base Image IDs do not match: ${original_foo_id} != ${rebuild_original_foo_id}"
  exit 1
else
    success "Base Image IDs match: ${original_foo_id} == ${rebuild_original_foo_id}"
fi

if [ "$original_foochild_id" != "$rebuild_original_foochild_id" ]
then
  error "Child Image IDs do not match: ${original_foochild_id} != ${rebuild_original_foochild_id}"
  exit 1
else
    success "Child Image IDs match: ${original_foochild_id} == ${rebuild_original_foochild_id}"
fi
