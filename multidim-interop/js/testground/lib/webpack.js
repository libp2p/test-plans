import webpack from 'webpack'

export function bundle(testFile) {
    webpack({
        entry: testFile,
    }, (err, stats) => {
        if (err || stats.hasErrors()) {
            if (err) {
                console.error(err.stack || err);
                if (err.details) {
                    console.error(err.details);
                }
                return;
            }

            const info = stats.toJson();

            if (stats.hasErrors()) {
                console.error(info.errors);
            }

            if (stats.hasWarnings()) {
                console.warn(info.warnings);
            }
        }
        // Done processing
    })
}
