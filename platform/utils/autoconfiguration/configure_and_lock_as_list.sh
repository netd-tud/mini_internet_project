#!/bin/bash
# This script takes a new-line separated list of ASes that are 
# to be overtaken (produced by scripts in the teaching-mini-internet repo).
# Besides adding the reference config, it will also update the password
# with a random one, as well as delete the authorized_keys file, to 
# lock out students and prevent them from accessing the reference config.

set -o errexit
set -o pipefail
set -o nounset

FOLLOW_UP_SCRIPT="./utils/autoconfiguration/configure_as.sh"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <numbers-file>" >&2
    exit 1
fi

NUMBERS_FILE="$1"

if [ ! -f "${NUMBERS_FILE}" ]; then
    echo "Numbers file does not exist: ${NUMBERS_FILE}" >&2
    exit 1
fi

if [ ! -x "${FOLLOW_UP_SCRIPT}" ]; then
    echo "Follow-up script must exist and be executable: ${FOLLOW_UP_SCRIPT}" >&2
    exit 1
fi

generate_password() {
    if command -v openssl > /dev/null 2>&1; then
        openssl rand -base64 32 | tr -d '=+/' | cut -c1-32
    else
        od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
    fi
}

while IFS= read -r number || [ -n "${number}" ]; do
    # Skip blank lines and comments.
    if [[ "${number}" =~ ^[[:space:]]*(#.*)?$ ]]; then
        continue
    fi

    if [[ ! "${number}" =~ ^[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
        echo "Invalid number: ${number}" >&2
        exit 1
    fi
    number="${BASH_REMATCH[1]}"

    container="${number}_ssh"
    password="$(generate_password)"

    if [ -z "${password}" ]; then
        echo "Failed to generate password for ${container}" >&2
        exit 1
    fi

    printf '%s\n%s\n' "${password}" "${password}" | docker exec -i "${container}" passwd root > /dev/null
    docker exec "${container}" rm /root/.ssh/authorized_keys
    "${FOLLOW_UP_SCRIPT}" --no-rpki "${number}" < /dev/tty

done < "${NUMBERS_FILE}"
