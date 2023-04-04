#!/usr/bin/env /bin/bash
set -eou pipefail

# sort all the files passed in by name, then hash them
echo "$@" | xargs -n1 | sort | xargs sha256sum | sha256sum | sed 's/.$//' | xargs
