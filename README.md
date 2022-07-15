## Bug description

`simple` folder contains a basic docker image with minimal commands. `simple-child` folder contains dockerfile which uses the image from `simple` as it's base image.
We next build the 2 images and export them to a registry cache. Now when we clear the cache and try to build the 2 images again this time using the registry cache (using --import-cache), we expect that all the layers from both the images are found in the cache and the digests of the produced images match the digests of the images which were previously generated. We see that for the image in `simple` the digest matches and all the layers are found in the cache, however for the image in `simple-child`, 1 layer (RUN sleep command) is not found in the cache and it's digest differs from the 1 created in the 1st step.

## How to reproduce

Clone this repository and run `sudo ./run-test.sh`.

The script will try to reproduce the issue with the following steps:
- Starts containerd and buildkitd (using containerd worker) and prunes the cache
- Builds the 2 images using `--export-cache` to cache it to a local registry and prints their digests
- Cleans the cache again and builds the 2 images using `--import-cache` to use the local registry cache and prints their digests
- Cleanup all started processes, registry etc.