#! /usr/bin/env bash
set -e
set -o pipefail
set -x

testground healthcheck --runner local:docker --fix
testground run composition -f ./compatibility/composition.toml  \
    --metadata-repo "${GITHUB_REPOSITORY}"            \
    --metadata-branch "${GITHUB_REF#refs/heads/}"     \
    --metadata-commit "${GITHUB_SHA}" | tee run.out

TGID=$(awk '/run is queued with ID/ {print $10}' <run.out)

while [ "${status}" != "complete" -a "${status}" != "canceled" ]
do
	sleep 120
	status=$(testground status -t "${TGID}" | awk '/Status/ {print $2}')
	echo "last polled status is ${status}"
	echo "${OUTPUT_STATUS}${status}"
done

echo "terminating remaining containers"
testground terminate --runner local:docker