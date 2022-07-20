#!/bin/bash
set -e

IMAGE=moby/buildkit:master-rootless

info() {
  echo $'=== \e[1m'$@$'\e[0m' >&2
}

error() {
  echo $'\e[1;31m'$@$'\e[0m' >&2
}

success() {
  echo $'\e[1;32m'$@$'\e[0m' >&2
}

start_registry() {
    info "Start local registry for caching"
    registry_cache=$(docker run -p 5000:5000 -d --name registry-cache registry:2)
}

stop_registry() {
  if [ -n "$registry_cache" ]
  then
    info "Stop local registry for caching"
    docker rm -vf $registry_cache
  fi
}

buildctl-daemonless() {
    docker run \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    -v $(pwd)/context:/context \
    -v $(pwd)/config.toml:/etc/buildkit/buildkitd.toml \
    -e BUILDKITD_FLAGS='--oci-worker-no-process-sandbox --config /etc/buildkit/buildkitd.toml' \
    --link registry-cache:registry-cache \
    --rm \
    -ti \
    --entrypoint buildctl-daemonless.sh \
    $links \
    ${IMAGE} \
    "$@"
}

function cleanup {
    stop_registry
    sudo ctr -n original image rm $(sudo ctr -n original images ls -q)
    sudo ctr -n original content rm $(sudo ctr -n original content ls -q)
}

pullAndInspectImage() {
  namespace="${1}"
  image="${2}"
  sudo ctr -n ${namespace} image pull --plain-http ${image} >&2
  image_id=$(sudo ctr -n ${namespace} images ls | grep ${image} | tr -s ' ' | cut -d ' ' -f 3)
  manifest=$(sudo ctr -n ${namespace} content get "${image_id}")
  #info "${1} manifest"
  #echo "${manifest}" | jq . >&2
  config_id=$(echo "${manifest}" | jq -r .config.digest)
  #info "${1} image config"
  #sudo ctr -n ${namespace} content get "${config_id}" | jq . >&2
  echo "${image_id}"
}

comapreImages() {
  namespace_one="${1}"
  image_one="${2}"
  namespace_two="${3}"
  image_two="${4}"
  info "Comparing manifests"
  manifest_one=$(sudo ctr -n ${namespace_one} content get ${image_one})
  manifest_two=$(sudo ctr -n ${namespace_two} content get ${image_two})
  diff --new-line-format='+%L' --old-line-format='-%L' --unchanged-line-format=' %L' <( printf '%s\n' "${manifest_one}" ) <( printf '%s\n' "${manifest_two}" ) || true

  info "Comparing configs"
  config_one_id=$(echo "${manifest_one}" | jq -r .config.digest)
  config_two_id=$(echo "${manifest_two}" | jq -r .config.digest)
  config_one=$(sudo ctr -n ${namespace_one} content get "${config_one_id}" | jq .)
  config_two=$(sudo ctr -n ${namespace_two} content get "${config_two_id}" | jq .)
  diff --new-line-format='+%L' --old-line-format='-%L' --unchanged-line-format=' %L' <( printf '%s\n' "${config_one}" ) <( printf '%s\n' "${config_two}" ) || true
}

trap cleanup EXIT ERR

start_registry

info "Building and exporting image"
buildctl-daemonless build . \
  --frontend dockerfile.v0 \
  --local context=/context \
  --local dockerfile=/context \
  --export-cache=type=registry,ref=registry-cache:5000/cache/image:debug  \
  -t registry-cache:5000/leaf:debug \
  --output=type=image,name=registry-cache:5000/image:debug,push=true \
  --progress=plain \
  --opt target=final

info "Pulling original image for inspection"
original_id=$(pullAndInspectImage original localhost:5000/image:debug)

info "Building (with import-from) image"
buildctl-daemonless build . \
  --frontend dockerfile.v0 \
  --local context=/context \
  --local dockerfile=/context \
  --import-cache=type=registry,ref=registry-cache:5000/cache/image:debug \
  --output type=image,name=registry-cache:5000/image:debug,push=true \
  -t registry-cache:5000/image:debug \
  --progress=plain \
  --opt target=final


info "Pulling rebuilt image for inspection"
rebuild_id=$(pullAndInspectImage rebuild localhost:5000/image:debug)

# Check if original and rebuild ids match
if [ "${original_id}" != "${rebuild_id}" ]
then
  error "original and rebuild image digests do not match: ${original_id} != ${rebuild_id}"
  comapreImages original ${original_id} rebuild ${rebuild_id}
  exit 1
else
    success "original and rebuild image digests match: ${original_id} == ${rebuild_id}"
fi
