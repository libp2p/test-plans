#!/bin/bash
# Output formatting functions for consistent UX across all test suites
# Provides banner, header, and list printing utilities with indentation

# The indentation is tracked by the INDENT global variable. These two helper
# functions manage the indentation of messages. Scripts should call `indent()`
# and `unindent()` in matched pairs so that the output is orderly.

export INDENT

# Increase the indendation level of messages
indent() {
  INDENT=$(( ${INDENT:-0} + 1 ))
  return 0
}

# Decrease the indentation level of messages
unindent() {
  INDENT=$(( ${INDENT:-0} - 1 ))
  (( INDENT < 0 )) && INDENT=0
  return 0
}

# Print the libp2p ASCII banner
# Usage:
#   print_banner
print_banner() {
  echo "" >&2
  echo "                        ╔╦╦╗  ╔═╗" >&2
  echo "▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ║╠╣╚╦═╬╝╠═╗ ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁" >&2
  echo "═══════════════════════ ║║║║║║║╔╣║║ ════════════════════════" >&2
  echo "▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ ╚╩╩═╣╔╩═╣╔╝ ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔" >&2
  echo "                            ╚╝  ╚╝" >&2
  echo "" >&2
  return 0
}

# Print a section header with underline
# Args:
#   $1: header_text - The header text to display
# Usage:
#   print_header "Building Docker images"
#   print_header "Checking dependencies"
print_header() {
  local header_text="$1"
  echo "╲ $header_text" >&2
  echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔" >&2
  return 0
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
  local -n items="$2"

  if [ ${#items[@]} -eq 0 ]; then
    print_iem "" "${list_name}: (none)"
    return
  fi

  print_iem "" "${list_name}:"
  indent
  for item in "${items[@]}"; do
    print_iem "-" "${item}"
  done
  unindent
  return 0
}

# Print a simple message with "DEBUG:" prefix and optional indentation to stderr
# Args:
#   $INDENT: indentation - number of 2-space indentations
#   $1: message - Message to print
# Usage:
#   print_debug "Cache Dir: /srv/cache"
#   print_debug "Workers: 4"
print_debug() {
  if [ "${DEBUG:-false}" == "true" ]; then
    local message="$1"
    print_iem "DEBUG:" "${message}" >&2
  fi
  return 0
}

# Same as above but uses echo -n instead
echo_debug() {
  local message="$1"
  print_iem "DEBUG:" "${message}" "true" >&2
  return 0
}

# Log debug (only if DEBUG=true)
# Usage: log_debug "message"
log_debug() {
  if [ "${DEBUG:-false}" == "true" ]; then
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $*"
    # Write to log file if available, otherwise to stderr
    if [ -n "${LOG_FILE:-}" ]; then
      echo "${msg}" >> "${LOG_FILE}"
    else
      echo "${msg}" >&2
    fi
  fi
}

# Print a simple message with arrow prefix and optional indentation
# Args:
#   $INDENT: indentation - number of 2-space indentations
#   $1: message - Message to print
# Usage:
#   print_message "Cache Dir: /srv/cache"
#   print_message "Workers: 4"
print_message() {
  local message="$1"
  print_iem "→" "${message}" >&2
  return 0
}

# Same as above but uses echo -n instead
echo_message() {
  local message="$1"
  print_iem "→" "${message}" "true" >&2
  return 0
}

# Log with timestamp
# Usage: log_message "message"
log_message() {
  local msg="[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"

  # Write to log file if available, otherwise to stderr
  if [ -n "${LOG_FILE:-}" ]; then
    echo "${msg}" >> "${LOG_FILE}"
  else
    echo "${msg}" >&2
  fi
}

# Print a success message with checkmark
# Args:
#   $1: message - Success message
# Usage:
#   print_success "All dependencies satisfied"
#   print_success "Loaded 30 implementations"
print_success() {
  local message="$1"
  print_iem "✓" "${message}" >&2
  return 0
}

# Same as above but uses echo -n instead
echo_success() {
  local message="$1"
  print_iem "✓" "${message}" "true" >&2
  return 0
}

# Print an error message with X mark
# Args:
#   $1: message - Error message
# Usage:
#   print_error "Dependency check failed"
#   print_error "File not found"
print_error() {
  local message="$1"
  print_iem "✗" "${message}" >&2
  return 0
}

# Same as above but uses echo -n instead
echo_error() {
  local message="$1"
  print_iem "✗" "${message}" "true" >&2
  return 0
}

# Log error with timestamp
# Usage: log_error "message"
log_error() {
  local msg="[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*"

  # Write to log file if available, otherwise to stderr
  if [ -n "${LOG_FILE:-}" ]; then
    echo "${msg}" >> "${LOG_FILE}"
  else
    echo "${msg}" >&2
  fi
}

# Print a message with indentation and emoji
# Args:
#   $INDENT: indentation - number of 2-space indentations
#   $1: emoji
#   $2: message
# Usage:
#   print_iem "→" "Workers: 4"
#   print_iem "✗" "File not found"
print_iem() {
  local emoji="$1"
  local message="$2"
  local no_newline="${3:-}" # if set/non-empty, use -n

  # Default of 0 indentation if unset or empty
  local indent_levels="${INDENT:-0}"

  # Build the prefix: emoji + space only if emoji is non-empty
  local prefix=""
  if [ -n "${emoji}" ]; then
    prefix="${emoji} "
  fi

  # Build the full text
  local output="${prefix}${message}"

  # Only apply indendation if > 0
  if (( indent_levels > 0)); then
    local indentation=$(printf '%*s' $((indent_levels * 2)) '')
    output="${indentation}${output}"
  fi

  # Print with or without newline
  if [ -n "${no_newline}" ]; then
    echo -n "${output}"
  else
    echo "${output}"
  fi
  return 0
}
