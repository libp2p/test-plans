export interface TestFilterOptions {
    nameFilter: string[] | null;
    nameIgnore: string[] | null;
    verbose: boolean;
}

/**
 * Parse raw filter strings into structured filter options
 */
export function parseFilterArgs(
    rawNameFilter: string,
    rawNameIgnore: string,
    verbose: boolean
): TestFilterOptions {
    let nameFilter: string[] | null = null;
    if (rawNameFilter) {
        if (verbose) {
            console.log("rawNameFilter: " + rawNameFilter);
        }
        nameFilter = rawNameFilter.split('|').map(item => item.trim()).filter(item => item.length > 0);
    }

    let nameIgnore: string[] | null = null;
    if (rawNameIgnore) {
        if (verbose) {
            console.log("rawNameIgnore: " + rawNameIgnore);
        }
        nameIgnore = rawNameIgnore.split('|').map(item => item.trim()).filter(item => item.length > 0);
    }

    return {
        nameFilter,
        nameIgnore,
        verbose
    };
}

/**
 * Check if a test name matches the filter criteria
 * Returns true if the name should be included, false if it should be filtered out
 */
export function matchesFilter(
    name: string,
    options: TestFilterOptions
): boolean {
    const { nameFilter, nameIgnore, verbose } = options;

    let accept: boolean = true;
    let reason: string = "";
    let result: string[] = ["Checking " + name];

    // Check if name matches any filter (if filters are provided)
    let filterMatch: string = "*";
    if (nameFilter && nameFilter.length > 0 && !nameFilter.some(n => {
        let msg: string = "filter match ('" + n + "')";
        let included: boolean = name.includes(n);

        if (included) {
            filterMatch = n;
        }

        if (verbose) {
            result.push("..." + (included ? "" : "NO ") + msg);
        }

        return included;
    })) {
        if (verbose) {
            result.push("...NOT selected");
        }
        reason = "NO filter match";
        accept = false;
    } else {
        if (verbose) {
            result.push("...selected because of ('" + filterMatch + "')");
        }
        reason = "filter match: '" + filterMatch + "'";
    }

    // Check if name matches any ignore pattern
    if (accept) {
        let ignoreMatch: string = "";
        if (nameIgnore && nameIgnore.length > 0 && nameIgnore.some(n => {
            let msg: string = "ignore match ('" + n + "')";
            let included: boolean = name.includes(n);

            if (included) {
                ignoreMatch = n;
            }

            if (verbose) {
                result.push("..." + (included ? "" : "NO ") + msg);
            }

            return included;
        })) {
            if (verbose) {
                result.push("...ignored because of ('" + ignoreMatch + "')");
            }
            reason = "ignore match: '" + ignoreMatch + "'";
            accept = false;
        } else {
            if (verbose) {
                result.push("...NOT ignored");
            }
        }
    }

    // Log result
    if (accept) {
        result.push("...ACCEPTED (" + reason + ")");
    } else {
        result.push("...REJECTED (" + reason + ")");
    }

    if (verbose) {
        console.log(result.join("\n\t"));
    } else {
        console.log(result.join(""));
    }

    return accept;
}
