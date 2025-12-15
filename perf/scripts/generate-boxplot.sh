#!/bin/bash
# Generate box plot visualizations from perf test results.yaml using gnuplot
#
# This script reads the results.yaml file and creates box plots for:
# - Upload throughput
# - Download throughput
# - Latency
#
# The box plots show the distribution of measurements across all tests,
# using the min, q1, median, q3, and max values from each test.

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <results.yaml> <output_dir>"
    exit 1
fi

RESULTS_FILE="$1"
OUTPUT_DIR="$2"

if [ ! -f "$RESULTS_FILE" ]; then
    echo "✗ Error: $RESULTS_FILE not found"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "→ Generating box plots..."

# Extract data for each metric and create gnuplot data files
extract_metric_data() {
    local metric="$1"  # upload, download, or latency
    local output_file="$2"
    local test_type="$3"  # baseline or main

    # Determine which section to read from
    local section="testResults"
    if [ "$test_type" = "baseline" ]; then
        section="baselineResults"
    fi

    # Count tests in this section
    local count=$(yq eval ".$section | length" "$RESULTS_FILE" 2>/dev/null || echo "0")

    if [ "$count" -eq 0 ]; then
        return 0
    fi

    # Extract each test's statistics
    for ((i=0; i<count; i++)); do
        local status=$(yq eval ".$section[$i].status" "$RESULTS_FILE" 2>/dev/null || echo "")

        # Only process passed tests
        if [ "$status" != "pass" ]; then
            continue
        fi

        # Check if this metric exists for this test
        local has_metric=$(yq eval ".$section[$i] | has(\"$metric\")" "$RESULTS_FILE" 2>/dev/null || echo "false")

        if [ "$has_metric" != "true" ]; then
            continue
        fi

        local name=$(yq eval ".$section[$i].name" "$RESULTS_FILE" 2>/dev/null || echo "unknown")
        local min=$(yq eval ".$section[$i].$metric.min" "$RESULTS_FILE" 2>/dev/null || echo "0")
        local q1=$(yq eval ".$section[$i].$metric.q1" "$RESULTS_FILE" 2>/dev/null || echo "0")
        local median=$(yq eval ".$section[$i].$metric.median" "$RESULTS_FILE" 2>/dev/null || echo "0")
        local q3=$(yq eval ".$section[$i].$metric.q3" "$RESULTS_FILE" 2>/dev/null || echo "0")
        local max=$(yq eval ".$section[$i].$metric.max" "$RESULTS_FILE" 2>/dev/null || echo "0")

        # Gnuplot box plot format: x_pos min q1 median q3 max label
        echo "$name|$min|$q1|$median|$q3|$max|$test_type" >> "$output_file"
    done
}

# Generate box plot for a specific metric
generate_boxplot() {
    local metric="$1"
    local metric_title="$2"
    local unit="$3"
    local data_file="$OUTPUT_DIR/${metric}_data.tmp"
    local output_file="$OUTPUT_DIR/boxplot-${metric}.png"

    # Remove old data file
    rm -f "$data_file"

    # Extract data from both baseline and main test results
    extract_metric_data "$metric" "$data_file" "baseline"
    extract_metric_data "$metric" "$data_file" "main"

    # Check if we have any data
    if [ ! -f "$data_file" ] || [ ! -s "$data_file" ]; then
        echo "  ✗ No data for $metric, skipping"
        return 0
    fi

    # Count number of data points
    local num_tests=$(wc -l < "$data_file")

    # Create gnuplot script
    cat > "$OUTPUT_DIR/${metric}_plot.gnuplot" <<'GNUPLOT_SCRIPT'
# Set terminal to PNG with good resolution
set terminal pngcairo size 1200,800 enhanced font 'Arial,10'
set output OUTPUT_FILE

# Set title and labels
set title PLOT_TITLE font 'Arial,14'
set ylabel Y_LABEL font 'Arial,12'
set xlabel "Tests" font 'Arial,12'

# Grid
set grid y

# Box plot styling
set style fill solid 0.5 border -1
set style data boxplot
set boxwidth 0.5

# X-axis configuration
set xtics rotate by -45
set xtics scale 0

# Auto-scale y-axis
set autoscale y

# Color definitions
baseline_color = "#4CAF50"  # Green
main_color = "#2196F3"      # Blue

# Read data and plot
set datafile separator "|"

# Plot boxes manually using candlesticks
plot DATA_FILE using 0:2:3:4:5:6:(stringcolumn(7) eq "baseline" ? baseline_color : main_color):xtic(1) \
    with candlesticks lc rgb variable linewidth 1.5 notitle whiskerbars, \
    '' using 0:4:4:4:4:(stringcolumn(7) eq "baseline" ? baseline_color : main_color) \
    with candlesticks lc rgb variable linewidth 2 notitle

# Legend
set key outside right top
set style rectangle fillcolor rgb "white" fillstyle solid 1.0 border -1
GNUPLOT_SCRIPT

    # Replace placeholders in gnuplot script
    sed -i "s|OUTPUT_FILE|'$output_file'|g" "$OUTPUT_DIR/${metric}_plot.gnuplot"
    sed -i "s|PLOT_TITLE|'Performance Test Results - $metric_title'|g" "$OUTPUT_DIR/${metric}_plot.gnuplot"
    sed -i "s|Y_LABEL|'$metric_title ($unit)'|g" "$OUTPUT_DIR/${metric}_plot.gnuplot"
    sed -i "s|DATA_FILE|'$data_file'|g" "$OUTPUT_DIR/${metric}_plot.gnuplot"

    # Run gnuplot
    if gnuplot "$OUTPUT_DIR/${metric}_plot.gnuplot" 2>/dev/null; then
        echo "  ✓ Generated $output_file"
        # Clean up temporary files
        rm -f "$data_file" "$OUTPUT_DIR/${metric}_plot.gnuplot"
    else
        echo "  ✗ Failed to generate $metric box plot"
        return 1
    fi
}

# Get units from first test result
get_unit() {
    local metric="$1"

    # Try baseline results first
    local unit=$(yq eval ".baselineResults[0].$metric.unit" "$RESULTS_FILE" 2>/dev/null || echo "")

    # If not found, try main results
    if [ -z "$unit" ] || [ "$unit" = "null" ]; then
        unit=$(yq eval ".testResults[0].$metric.unit" "$RESULTS_FILE" 2>/dev/null || echo "")
    fi

    # Default units
    case "$metric" in
        upload|download) echo "${unit:-Mbps}" ;;
        latency) echo "${unit:-ms}" ;;
        *) echo "" ;;
    esac
}

# Generate box plots for each metric
upload_unit=$(get_unit "upload")
download_unit=$(get_unit "download")
latency_unit=$(get_unit "latency")

generate_boxplot "upload" "Upload" "$upload_unit"
generate_boxplot "download" "Download" "$download_unit"
generate_boxplot "latency" "Latency" "$latency_unit"

echo "✓ Box plot generation complete"
