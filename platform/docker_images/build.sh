#!/bin/bash
#
# build all images

set -o errexit
set -o pipefail
set -o nounset

images=(base base_supervisor host router ixp ssh measurement dns switch matrix vpn vlc hostm routinator krill webserver history)

for image in "${images[@]}"; do
    echo 'Build '$image
    docker build --tag="d_${image}" "docker_images/${image}/"
done
