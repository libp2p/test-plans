#!/bin/bash
set -eou pipefail

WORKINGDIR=$(mktemp -d); 

function cleanup {
    rm -r $WORKINGDIR;
}
trap cleanup EXIT

cp -r ../v0.23/* $WORKINGDIR;
cp ./23To22.patch $WORKINGDIR;
cd $WORKINGDIR;
patch -s -p1 < 23To22.patch;
echo "{\"imageID\": \"$(docker build . -q)\"}"
