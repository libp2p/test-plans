#!/bin/bash
# Output formatting functions for consistent UX across all test suites
# Provides banner, header, and list printing utilities

# Print the libp2p ASCII banner
# Usage:
#   print_banner
print_banner() {
    echo ""
    echo "                        ╔╦╦╗  ╔═╗"
    echo "▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ║╠╣╚╦═╬╝╠═╗ ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁"
    echo "═══════════════════════ ║║║║║║║╔╣║║ ════════════════════════"
    echo "▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ ╚╩╩═╣╔╩═╣╔╝ ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    echo "                            ╚╝  ╚╝"
    echo ""
}

# Print a section header with underline
# Args:
#   $1: header_text - The header text to display
# Usage:
#   print_header "Building Docker images"
#   print_header "Checking dependencies"
print_header() {
    local header_text="$1"
    echo "╲ $header_text"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
}

# Print a named list with indentation
# Args:
#   $1: list_name - Name of the list (e.g., "implementations", "baselines")
#   $2+: items - Items to print (as separate arguments or array expansion)
# Usage:
#   print_list "implementations" "rust-v0.56" "go-v0.45" "python-v0.4"
#   print_list "baselines" "${baseline_array[@]}"
print_list() {
    local list_name="$1"
    shift
    local items=("$@")

    if [ ${#items[@]} -eq 0 ]; then
        echo "${list_name}: (none)"
        return
    fi

    echo "${list_name}:"
    for item in "${items[@]}"; do
        echo "  - $item"
    done
}

# Print a simple message with arrow prefix
# Args:
#   $1: message - Message to print
# Usage:
#   print_message "Cache Dir: /srv/cache"
#   print_message "Workers: 4"
print_message() {
    local message="$1"
    echo "→ $message"
}

# Print a success message with checkmark
# Args:
#   $1: message - Success message
# Usage:
#   print_success "All dependencies satisfied"
#   print_success "Loaded 30 implementations"
print_success() {
    local message="$1"
    echo "✓ $message"
}

# Print an error message with X mark
# Args:
#   $1: message - Error message
# Usage:
#   print_error "Dependency check failed"
#   print_error "File not found"
print_error() {
    local message="$1"
    echo "✗ $message"
}

# Print an indented success message (with leading spaces for nested output)
# Args:
#   $1: message - Success message
# Usage:
#   print_success_indented "Loaded 30 implementations"
print_success_indented() {
    local message="$1"
    echo "  ✓ $message"
}

# Print an indented message (with leading spaces for nested output)
# Args:
#   $1: message - Message to print
# Usage:
#   print_message_indented "Expanded to: rust-v0.56"
print_message_indented() {
    local message="$1"
    echo "  → $message"
}
