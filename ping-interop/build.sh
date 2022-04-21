#! /usr/bin/env bash
set -e
set -o pipefail
set -x

# Build every plan and store the generated artifact.
# similar to https://github.com/testground/testground/blob/master/integration_tests/01_k8s_kind_placebo_ok.sh

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"

INPUT_TESTPLAN_A=${INPUT_TESTPLAN_A:-$INPUT_TESTPLAN}
INPUT_TESTPLAN_B=${INPUT_TESTPLAN_B:-$INPUT_TESTPLAN_A}

INPUT_VERSION_A=${INPUT_VERSION_A:-$INPUT_VERSION}
INPUT_VERSION_B=${INPUT_VERSION_B:-$INPUT_VERSION_A}

echo "testing ${SCRIPT_DIR}"
echo "instance a: ${INPUT_TESTPLAN_A} ${INPUT_VERSION_A}"
echo "instance b: ${INPUT_TESTPLAN_B} ${INPUT_VERSION_B}"

mkdir -p ${HOME}/testground/plans/libp2p # TODO: find if we can remove this, maybe create a ticket.
testground plan import --from ${SCRIPT_DIR} --name "libp2p/ping-interop"

# TODO: according to the doc this should work: --dep github.com/libp2p/go-libp2p=${INPUT_VERSION_A} \
testground build single --wait \
    --builder docker:go \
    --dep github.com/libp2p/go-libp2p=github.com/libp2p/go-libp2p@${INPUT_VERSION_A} \
    --plan libp2p/ping-interop/${INPUT_TESTPLAN_A} 2>&1 | tee build.out
export ARTIFACT_VERSION_A=$(awk -F\" '/generated build artifact/ {print $8}' <build.out)

testground build single --wait \
    --builder docker:go \
    --dep github.com/libp2p/go-libp2p=github.com/libp2p/go-libp2p@${INPUT_VERSION_B} \
    --plan libp2p/ping-interop/${INPUT_TESTPLAN_B} 2>&1 | tee build.out
export ARTIFACT_VERSION_B=$(awk -F\" '/generated build artifact/ {print $8}' <build.out)

# testground build single --wait \
#     --builder docker:go \
#     --plan ping-interop/go-v0.18.0 2>&1 | tee build.out
# export ARTIFACT_GO_VERSION_OLD=$(awk -F\" '/generated build artifact/ {print $8}' <build.out)

# testground build single --wait \
#     --builder docker:go \
#     --plan ping-interop/go-v0.19.0 2>&1 | tee build.out
# export ARTIFACT_GO_VERSION_NEW=$(awk -F\" '/generated build artifact/ {print $8}' <build.out)

envsubst < "${SCRIPT_DIR}/_compositions/2-versions.template.toml" > "${SCRIPT_DIR}/_compositions/2-versions.toml"
