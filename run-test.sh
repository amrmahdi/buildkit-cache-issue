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
    removeImages || true
    stop_registry
}

removeImages() {
    title "Removing images from docker daemon"
    docker rmi $(docker images localhost:5000/* -a -q)
}

trap cleanup EXIT ERR

start_registry

title "Building and exporting parent image"
buildctl-daemonless build . --frontend dockerfile.v0 --local context=/context/simple --local dockerfile=/context/simple --output type=image,name=registry-cache:5000/foo:bar,push=true --export-cache=type=registry,ref=registry-cache:5000/cache/simple:0

title "Pulling images to docker daemon for inspection"
docker pull localhost:5000/foo:bar
original_foo_id=$(docker inspect --format='{{index .RepoDigests 0}}' localhost:5000/foo:bar | cut -d'@' -f 2)

title "Building and exporting child image"
buildctl-daemonless build . --opt build-arg:BASE=registry-cache:5000/foo:bar@${original_foo_id} --frontend dockerfile.v0 --local context=/context/simple-child --local dockerfile=/context/simple-child --output type=image,name=registry-cache:5000/foochild:bar,push=true --export-cache=type=registry,name=registry-cache:5000/cache/simplechild:0

title "Pulling images to docker daemon for inspection"
docker pull localhost:5000/foochild:bar
original_foochild_id=$(docker inspect --format='{{index .RepoDigests 0}}' localhost:5000/foochild:bar | cut -d'@' -f 2)

removeImages

title "Building (with import-from) parent image"
buildctl-daemonless build . --frontend dockerfile.v0 --local context=/context/simple --local dockerfile=/context/simple --output type=image,name=registry-cache:5000/foo:bar,push=true --import-cache=type=registry,ref=registry-cache:5000/cache/simple:0

title "Building (with import-from) child image"
buildctl-daemonless build . --frontend dockerfile.v0 --opt build-arg:BASE=registry-cache:5000/foo:bar@${original_foo_id} --local context=/context/simple-child --local dockerfile=/context/simple-child --output type=image,name=registry-cache:5000/foochild:bar,push=true --import-cache=type=registry,name=registry-cache:5000/cache/simplechild:0

title "Pulling images to docker daemon for inspection"
docker pull localhost:5000/foo:bar
docker pull localhost:5000/foochild:bar

rebuild_original_foo_id=$(docker inspect --format='{{index .RepoDigests 0}}' localhost:5000/foo:bar | cut -d'@' -f 2)
rebuild_original_foochild_id=$(docker inspect --format='{{index .RepoDigests 0}}' localhost:5000/foochild:bar | cut -d'@' -f 2)

# Check if the images are the same
if [ "$original_foo_id" != "$rebuild_original_foo_id" ]
then
  error "Base Image digests do not match: ${original_foo_id} != ${rebuild_original_foo_id}"
  exit 1
else
    success "Base Image digests match: ${original_foo_id} == ${rebuild_original_foo_id}"
fi

if [ "$original_foochild_id" != "$rebuild_original_foochild_id" ]
then
  error "Child Image digests do not match: ${original_foochild_id} != ${rebuild_original_foochild_id}"
  exit 1
else
    success "Child Image digests match: ${original_foochild_id} == ${rebuild_original_foochild_id}"
fi
