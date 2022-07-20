## Issue description

When building this simple [Dockerfile](./context/Dockerfile) and exporting the resulting layers to cache using `--export-cache`, one except that when the Dockerfile is rebuilt with importing the same cache using `--import-cache` that the resulting images from both the initial build and the rebuild would be the same. 

However, the resulting images are not the same, due to a mismatch in the image config cause by a different `created` date on one of the layers, specifically the `COPY --from=builder /src/ /src/` on line 7.

## How to reproduce

Clone this repository and run `make run`.

This will start a local registry to use for importing and exporting the cache, as well as a source to inspect the images from.

The script will build the image once and export the result to the registry cache, then will build it again but this time exporting the cache from the registry.

Finally the script will compare the resulting images digest, and if different, runs a `diff` on both the image manifests and the image configs.

## Requirements
* bash
* make
* Docker
* containerd
* ctr 
* diff