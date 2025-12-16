#!/bin/bash
# Generate box plot visualizations from perf test results.yaml using yq and gnuplot
# Based on the user's plot.sh script format

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

# Get counts dynamically from both arrays
BASELINE_COUNT=$(yq '.baselineResults | length' "$RESULTS_FILE" 2>/dev/null || echo "0")
TEST_COUNT=$(yq '.testResults | length' "$RESULTS_FILE" 2>/dev/null || echo "0")

echo "  → Found $BASELINE_COUNT baseline results and $TEST_COUNT test results"

# Data files
UPLOAD_BOX="$OUTPUT_DIR/upload_box.dat"
UPLOAD_OUT="$OUTPUT_DIR/upload_out.dat"
DOWNLOAD_BOX="$OUTPUT_DIR/download_box.dat"
DOWNLOAD_OUT="$OUTPUT_DIR/download_out.dat"
LATENCY_BOX="$OUTPUT_DIR/latency_box.dat"
LATENCY_OUT="$OUTPUT_DIR/latency_out.dat"

# Initialize data files with headers
cat > "$UPLOAD_BOX" <<'EOF'
# idx	label	min	q1	median	q3	max
EOF
cat > "$UPLOAD_OUT" <<'EOF'
# idx	outlier_value
EOF
cat > "$DOWNLOAD_BOX" <<'EOF'
# idx	label	min	q1	median	q3	max
EOF
cat > "$DOWNLOAD_OUT" <<'EOF'
# idx	outlier_value
EOF
cat > "$LATENCY_BOX" <<'EOF'
# idx	label	min	q1	median	q3	max
EOF
cat > "$LATENCY_OUT" <<'EOF'
# idx	outlier_value
EOF

# Function to add box data for a metric
add_box_data() {
    local array_path="$1"
    local array_idx="$2"
    local metric="$3"
    local boxfile="$4"
    local idx="$5"

    # Get name and stats
    local name min q1 med q3 max
    name=$(yq -r "${array_path}[${array_idx}].name" "$RESULTS_FILE")
    # Insert newline before '(' to create two-line labels
    name="${name/ (/\\n(}"
    read -r min q1 med q3 max <<< $(yq -r "${array_path}[${array_idx}].${metric} | [.min, .q1, .median, .q3, .max] | @tsv" "$RESULTS_FILE")

    # Only add if we have valid data
    if [ "$med" != "null" ] && [ -n "$med" ]; then
        printf "%d\t\"%s\"\t%s\t%s\t%s\t%s\t%s\n" "$idx" "$name" "$min" "$q1" "$med" "$q3" "$max" >> "$boxfile"
    fi
}

# Function to add outlier data for a metric
add_outlier_data() {
    local array_path="$1"
    local array_idx="$2"
    local metric="$3"
    local outfile="$4"
    local idx="$5"

    # Get outliers and prepend idx to each line
    local outlier_count
    outlier_count=$(yq "${array_path}[${array_idx}].${metric}.outliers | length" "$RESULTS_FILE" 2>/dev/null || echo "0")
    if [ "$outlier_count" -gt 0 ]; then
        yq -r "${array_path}[${array_idx}].${metric}.outliers[]" "$RESULTS_FILE" | while read -r outlier; do
            [ -n "$outlier" ] && printf "%d\t%s\n" "$idx" "$outlier" >> "$outfile"
        done
    fi
}

# =============== UPLOAD ===============
echo "  → Extracting upload data..."
idx=1

# Iterate over baselineResults
for i in $(seq 0 $((BASELINE_COUNT-1))); do
    add_box_data ".baselineResults" "$i" "upload" "$UPLOAD_BOX" "$idx"
    add_outlier_data ".baselineResults" "$i" "upload" "$UPLOAD_OUT" "$idx"
    ((idx++))
done

# Iterate over testResults
for i in $(seq 0 $((TEST_COUNT-1))); do
    add_box_data ".testResults" "$i" "upload" "$UPLOAD_BOX" "$idx"
    add_outlier_data ".testResults" "$i" "upload" "$UPLOAD_OUT" "$idx"
    ((idx++))
done

# =============== DOWNLOAD ===============
echo "  → Extracting download data..."
idx=1

# Iterate over baselineResults
for i in $(seq 0 $((BASELINE_COUNT-1))); do
    add_box_data ".baselineResults" "$i" "download" "$DOWNLOAD_BOX" "$idx"
    add_outlier_data ".baselineResults" "$i" "download" "$DOWNLOAD_OUT" "$idx"
    ((idx++))
done

# Iterate over testResults
for i in $(seq 0 $((TEST_COUNT-1))); do
    add_box_data ".testResults" "$i" "download" "$DOWNLOAD_BOX" "$idx"
    add_outlier_data ".testResults" "$i" "download" "$DOWNLOAD_OUT" "$idx"
    ((idx++))
done

# =============== LATENCY ===============
echo "  → Extracting latency data..."
idx=1

# Iterate over baselineResults
for i in $(seq 0 $((BASELINE_COUNT-1))); do
    add_box_data ".baselineResults" "$i" "latency" "$LATENCY_BOX" "$idx"
    add_outlier_data ".baselineResults" "$i" "latency" "$LATENCY_OUT" "$idx"
    ((idx++))
done

# Iterate over testResults
for i in $(seq 0 $((TEST_COUNT-1))); do
    add_box_data ".testResults" "$i" "latency" "$LATENCY_BOX" "$idx"
    add_outlier_data ".testResults" "$i" "latency" "$LATENCY_OUT" "$idx"
    ((idx++))
done

# =============== GNUPlot scripts using candlesticks ===============
# Candlesticks format: x:box_min:whisker_min:whisker_max:box_max
# Columns: 1=idx, 2=label, 3=min, 4=q1, 5=median, 6=q3, 7=max
# Using: 1:4:3:7:6 maps to x:q1:min:max:q3

# Calculate xrange based on number of tests
TOTAL_TESTS=$((BASELINE_COUNT + TEST_COUNT))
XMAX=$(echo "$TOTAL_TESTS + 1.2" | bc -l)

cat > "$OUTPUT_DIR/upload.gp" <<EOF
set terminal pngcairo size 1400,1400 enhanced font 'Arial,14'
set output '$OUTPUT_DIR/boxplot-upload.png'
set title 'Upload Throughput Comparison'
set ylabel 'Throughput (Gbps)'
set yrange [0:*]
set grid y
set boxwidth 0.5
set style fill solid 0.25 border lc rgb 'black'
set xtics center font ',11'
set bmargin 5
set rmargin 8
set xrange [0.3:$XMAX]

# Box from q1 to q3, whiskers from min to max, median as line, median labels on right
plot '$UPLOAD_BOX' using 1:4:3:7:6:xticlabels(2) notitle with candlesticks lc rgb 'blue' lw 2 whiskerbars 0.5, '$UPLOAD_BOX' using 1:5:5:5:5 notitle with candlesticks lc rgb 'black' lw 2, '$UPLOAD_OUT' using 1:2 with points pt 7 ps 1.5 lc rgb 'red' title 'outliers', '$UPLOAD_BOX' using (\$1+0.35):5:5 with labels font ',11' notitle
EOF

cat > "$OUTPUT_DIR/download.gp" <<EOF
set terminal pngcairo size 1400,1400 enhanced font 'Arial,14'
set output '$OUTPUT_DIR/boxplot-download.png'
set title 'Download Throughput Comparison'
set ylabel 'Throughput (Gbps)'
set yrange [0:*]
set grid y
set boxwidth 0.5
set style fill solid 0.25 border lc rgb 'black'
set xtics center font ',11'
set bmargin 5
set rmargin 8
set xrange [0.3:$XMAX]

# Box from q1 to q3, whiskers from min to max, median as line, median labels on right
plot '$DOWNLOAD_BOX' using 1:4:3:7:6:xticlabels(2) notitle with candlesticks lc rgb 'blue' lw 2 whiskerbars 0.5, '$DOWNLOAD_BOX' using 1:5:5:5:5 notitle with candlesticks lc rgb 'black' lw 2, '$DOWNLOAD_OUT' using 1:2 with points pt 7 ps 1.5 lc rgb 'red' title 'outliers', '$DOWNLOAD_BOX' using (\$1+0.35):5:5 with labels font ',11' notitle
EOF

cat > "$OUTPUT_DIR/latency.gp" <<EOF
set terminal pngcairo size 1400,1400 enhanced font 'Arial,14'
set output '$OUTPUT_DIR/boxplot-latency.png'
set title 'Latency Comparison'
set ylabel 'Latency (ms)'
set yrange [0:*]
set grid y
set boxwidth 0.5
set style fill solid 0.25 border lc rgb 'black'
set xtics center font ',11'
set bmargin 5
set rmargin 8
set xrange [0.3:$XMAX]

# Box from q1 to q3, whiskers from min to max, median as line, median labels on right
plot '$LATENCY_BOX' using 1:4:3:7:6:xticlabels(2) notitle with candlesticks lc rgb 'blue' lw 2 whiskerbars 0.5, '$LATENCY_BOX' using 1:5:5:5:5 notitle with candlesticks lc rgb 'black' lw 2, '$LATENCY_OUT' using 1:2 with points pt 7 ps 1.5 lc rgb 'red' title 'outliers', '$LATENCY_BOX' using (\$1+0.35):5:5 with labels font ',11' notitle
EOF

# =============== Generate plots ===============
echo "  → Generating plots with gnuplot..."

if gnuplot "$OUTPUT_DIR/upload.gp" 2>/dev/null; then
    echo "  ✓ Generated boxplot-upload.png"
else
    echo "  ✗ Failed to generate upload box plot"
fi

if gnuplot "$OUTPUT_DIR/download.gp" 2>/dev/null; then
    echo "  ✓ Generated boxplot-download.png"
else
    echo "  ✗ Failed to generate download box plot"
fi

if gnuplot "$OUTPUT_DIR/latency.gp" 2>/dev/null; then
    echo "  ✓ Generated boxplot-latency.png"
else
    echo "  ✗ Failed to generate latency box plot"
fi

# Clean up temporary files
rm -f "$OUTPUT_DIR"/*.gp "$OUTPUT_DIR"/*.dat

echo "✓ Box plot generation complete"
