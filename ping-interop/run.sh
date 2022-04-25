#! /usr/bin/env bash
set -e
set -o pipefail
set -x

# See original code:
# https://github.com/galargh/testground-github-action/blob/master/entrypoint.sh

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
if [ "${GITHUB_ACTIONS}" = "true" ]; then SLEEP_TIME=20; else SLEEP_TIME=2; fi

testground healthcheck --runner local:docker --fix

testground run composition -f "${SCRIPT_DIR}/_compositions/2-versions.toml"  \
    --metadata-repo "${GITHUB_REPOSITORY}"            \
    --metadata-branch "${GITHUB_REF#refs/heads/}"     \
    --metadata-commit "${GITHUB_SHA}" | tee run.out

TGID=$(awk '/run is queued with ID/ {print $10}' <run.out)

while [ "${status}" != "complete" -a "${status}" != "canceled" ]
do
	sleep ${SLEEP_TIME}
	status=$(testground status -t "${TGID}" | awk '/Status/ {print $2}')
	echo "last polled status is ${status}"
	echo "${OUTPUT_STATUS}${status}"
done

# NOTE: we skip this from the original script because
#		this will likely kill sidecar & other relevant containers.
# echo "terminating remaining containers"
# testground terminate --runner local:docker

echo -n "Testground ended: "; date

echo getting extended status
testground status -t "${TGID}" --extended  | tee extendedstatus.out

# Get the extened status, which includes a "Result" section.
# Capture the line that occurs after "Result:"
extstatus=$(awk '/Result/ {getline; print $0}' <extendedstatus.out)

# First off, there are control characters in this output, and we need to remove that.
# https://github.com/testground/testground/issues/1214
extstatus=$(echo "${extstatus}" | tr -d "[:cntrl:]" |  sed 's/\[0m//g')

# test if we got a result at all. The result might be "null". A null result means most likely the
# job was canceled before it began for some reason.
if [ "${extstatus}" == "null" ]
then
	echo "${OUTPUT_OUTCOME}failure/canceled"
	exit 1
fi

# Now find the outcome of the test. The extended result is going to look something like this:
# {"journal":{"events":{},"pods_statuses":{}},"outcome":"success","outcomes":{"providers":{"ok":1,"total":1},"requestors":{"ok":1,"total":1}}}

outcome=$(echo "${extstatus}" | jq ".outcome")

echo "the extended status was ${extstatus}"
echo "The outcome of this test was ${outcome}"
echo "${OUTPUT_OUTCOME}${outcome}"

test "${outcome}" = "\"success\"" && exit 0 || exit 1
