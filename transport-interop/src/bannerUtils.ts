/**
 * Generate a centered banner with a title
 *
 * @param title - The text to display in the banner
 * @param width - Total width of the banner (default: 80)
 * @param char - Character to use for the banner border (default: "=")
 * @returns The formatted banner string
 *
 * @example
 * createBanner("SELECTED TESTS (5)", 80, "=")
 * // Returns: "======================== SELECTED TESTS (5) ========================"
 */
export function createBanner(title: string, width: number = 80, char: string = "="): string {
    if (title.length === 0) {
        return char.repeat(width);
    }

    const totalPadding = width - title.length - 2; // -2 for spaces around title

    // Handle case where title is too long
    if (totalPadding < 2) {
        return char.repeat(2) + " " + title + " " + char.repeat(2);
    }

    const leftPadding = Math.floor(totalPadding / 2);
    const rightPadding = Math.ceil(totalPadding / 2);

    return char.repeat(leftPadding) + " " + title + " " + char.repeat(rightPadding);
}

/**
 * Display selected tests banner with a list of test names
 *
 * @param testNames - Array of test names to display
 * @param width - Total width of the banner (default: 80)
 *
 * @example
 * displaySelectedTestsBanner(["rust-v0.53 x rust-v0.53 (tcp)", "rust-v0.53 x rust-v0.53 (quic)"])
 * // Outputs:
 * // ============================ SELECTED TESTS (2) ============================
 * //   • rust-v0.53 x rust-v0.53 (tcp)
 * //   • rust-v0.53 x rust-v0.53 (quic)
 * // ============================================================================
 */
export function displaySelectedTestsBanner(testNames: string[], width: number = 80): void {
    console.log("\n" + createBanner(`SELECTED TESTS (${testNames.length})`, width, "="));
    testNames.forEach(name => console.log(`  • ${name}`));
    console.log(createBanner("", width, "=") + "\n");
}
