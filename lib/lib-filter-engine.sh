#!/bin/bash
# Common filter engine for test/baseline/relay/router filtering
# Provides recursive alias expansion with loop detection, proper inversion, and deduplication

# Source formatting library if not already loaded
if ! type indent &>/dev/null; then
  _this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$_this_script_dir/lib-output-formatting.sh"
fi

# Prints a filter expansion
# Args:
#   $1: orig_var - The name of the global variable with the original filter string
#   $2: exp_var - The name of the global variable with the expanded filter string
#   $3: name - The name of the filter string (e.g. "Test select")
#   $4: empty - The string to display if the filter was not given (e.g. "No test-select specified (will include all implementations)")
print_filter_expansion() {
  local orig_var=$1
  local exp_var=$2
  local name=$3
  local empty=$4

  if [ -n "${!orig_var}" ]; then
    print_message "${name}: ${!orig_var}"
    if [[ "${!orig_var} != ${!exp_var} " ]]; then
      indent
      print_success "Expanded to: ${!exp_var}"
      unindent
    fi
  else
    print_message "${empty}"
  fi
}

_resolve_alias() {
  local alias_name=$1
  local -n processed_aliases_ref=$2
  local -n value_ref=$3

  print_debug "_resolve_alias()"
  indent
  print_debug "alias_name = ${alias_name}"
  print_debug "processed_aliases = ${processed_aliases_ref}"

  # Check for circular reference
  if [[ " ${processed_aliases_ref} " == *" ${alias_name} "* ]]; then
    print_error "Circular alias reference detected in chain: ${processed_aliases_ref} -> ${alias_name}"
    unindent
    return 1
  fi

  # Get alias value from global ALIASES array
  value_ref="${ALIASES[${alias_name}]:-}"
  if [ -z "${value_ref}" ]; then
    # Unknown alias - return empty (not an error, just undefined)
    debug_print "Unknown alias"
    unindent
    return 0
  fi

  # Add current alias to processed set
  processed_aliases_ref="${processed_aliases_ref} ${alias_name}"

  print_debug "alias_value = ${value_ref}"
  unindent
  return 0
}

_expand_recursive() {
  local filter_string=$1
  local -n all_names_ref=$2
  local -n processed_aliases_ref=$3
  local -n result_parts_ref=$4

  print_debug "_expand_recursive()"
  indent
  print_debug "filter_string = ${filter_string}"
  local rp=$(printf '%s\n' "${result_parts_ref[@]}" | paste -sd'|')
  print_debug "result_parts_ref = ${rp}"

  IFS='|' read -ra parts <<< "$filter_string"
  for part in "${parts[@]}"; do
    # Skip empty parts
    [ -z "$part" ] && continue

    # Remove shell escaping from ! if present
    part="${part#\\}"

    print_debug "part: ${part}"
    indent

    if [[ "$part" =~ ^!~(.+)$ ]]; then
      # Inverted alias: !~alias
      # Step 1: Recursively expand the alias
      local alias_name="${BASH_REMATCH[1]}"
      local value=""
      _resolve_alias "$alias_name" "${!processed_aliases_ref}" value || {
        unindent
        unindent
        return 1
      }
      local expanded_parts=()
      _expand_recursive "${value}" "${!all_names_ref}" "${!processed_aliases_ref}" expanded_parts || {
        unindent
        unindent
        return 1
      }

      # Deduplicate
      readarray -t expanded_parts < <(printf '%s\n' "${expanded_parts[@]}" | sort -u)

      # Step 2: Expand to all names that DON'T match ANY of the expanded parts
      # This means: if name matches ANY pattern in the expansion, exclude it
      # This is the inversion step
      #
      # Example
      #
      # Given:
      # all_names_ref=("one", "two", "three")
      # expanded_parts=("two", "three")
      #
      # Then:
      # result_parts_ref+=("one")
      #
      # Why? Because "one" doesn't match "two" or "three", "two" matches "two",
      # and "three" matches "three"
      #
      local ep=$(printf '%s\n' "${expanded_parts[@]}" | paste -sd'|')
      print_debug "Inverting: ${ep}"
      indent
      for name in "${all_names_ref[@]}"; do
        local matches_any=false
        for pattern in "${expanded_parts[@]}"; do
          if [[ "$name" == *"$pattern"* ]]; then
            matches_any=true
            #print_debug "${name} match...excluding"
            break
          fi
        done

        # If name does NOT match any pattern, include it
        if [ "$matches_any" = false ]; then
          #print_debug "${name} no match...including"
          local rp=$(printf '%s\n' "${result_parts_ref[@]}" | paste -sd'|')
          print_debug "${rp} += ${name}"
          result_parts_ref+=("${name}")
        fi
      done
      unindent

      local rp=$(printf '%s\n' "${result_parts_ref[@]}" | paste -sd'|')
      local ep=$(printf '%s\n' "${expanded_parts[@]}" | paste -sd'|')
      print_debug "result_parts_ref = ${rp}"
      print_debug "expanded_parts = ${ep}"

    elif [[ "$part" =~ ^~(.+)$ ]]; then
      # Regular alias: ~alias
      local alias_name="${BASH_REMATCH[1]}"
      local value=""
      _resolve_alias "${alias_name}" "${!processed_aliases_ref}" value || {
        unindent
        unindent
        return 1
      }
      print_debug "${alias_name} -> ${value}"
      #local expanded_parts=()
      _expand_recursive "${value}" "${!all_names_ref}" "${!processed_aliases_ref}" "${!result_parts_ref}" || {
        unindent
        unindent
        return 1
      }

    elif [[ "$part" =~ ^!(.+)$ ]]; then
      # Inverted value: !pattern
      # Expand to all names that DON'T contain the pattern
      local pattern="${BASH_REMATCH[1]}"

      for name in "${all_names_ref[@]}"; do
        if [[ "$name" != *"$pattern"* ]]; then
          #print_debug "${name} no match...including"
          local rp=$(printf '%s\n' "${result_parts_ref[@]}" | paste -sd'|')
          print_debug "${rp} += ${name}"
          result_parts_ref+=("${name}")
        fi
      done

    else
      # Regular value: pattern
      #print_debug "${part}...including"
      local rp=$(printf '%s\n' "${result_parts_ref[@]}" | paste -sd'|')
      print_debug "${rp} += ${part}"
      result_parts_ref+=("${part}")
    fi
    unindent
  done
  local result=$(printf '%s\n' "${result_parts_ref[@]}" | sort -u | paste -sd'|')
  print_debug "${filter_string} => ${result}"
  unindent
  return 0
}

# Expand a full filter string with recursive alias expansion, inversion, and deduplication
# Args:
#   $1: filter_string - Raw filter string (e.g., "rust|!go|~stable|!~failing")
#   $2: all_names_ref - Name of array variable containing all possible names (for negation expansion)
# Returns:
#   Fully expanded, deduplicated pipe-separated string
# Usage:
#   all_names=("rust-v0.56" "go-v0.45" "python-v0.4")
#   result=$(expand_filter_string "~rust|!go" all_names)
expand_filter_string() {
  local filter_string="$1"
  local -n all_names_ref=$2  # Name reference to array

  print_debug "expand_filter_string()"
  indent
  print_debug "filter_string = ${filter_string}"
  all_names=$(printf '%s\n' "${all_names_ref[@]}" | sort -u | paste -sd'|')
  print_debug "all_names_ref = ${all_names}"

  # Empty filter returns empty
  if [ -z "$filter_string" ]; then
    unindent
    return 0
  fi

  local result_parts=()
  local processed_aliases=""
  _expand_recursive "$filter_string" "${!all_names_ref}" processed_aliases result_parts || {
    unindent
    return 1
  }

  # Deduplicate and join
  if [ ${#result_parts[@]} -eq 0 ]; then
    result=""
  else
    result=$(printf '%s\n' "${result_parts[@]}" | sort -u | paste -sd'|')
  fi

  print_debug "result = ${result}"
  unindent
  echo "${result}"
}

# Generic matching: check if a name matches any pattern in a filter string
# Args:
#   $1: name - The name to check
#   $2: filter_string - Pipe-separated filter (already expanded, no aliases)
# Returns:
#   0 (true) if name matches any pattern, 1 (false) otherwise
# Usage:
#   filter_matches "rust-v0.56" "rust|go" && echo "matches"
filter_matches() {
  local name="$1"
  local filter_string="$2"

  # Empty filter matches nothing (return false)
  [ -z "$filter_string" ] && return 1

  IFS='|' read -ra patterns <<< "$filter_string"
  for pattern in "${patterns[@]}"; do
    [ -z "$pattern" ] && continue
    [[ "$name" == *"$pattern"* ]] && return 0
  done

  return 1
}

# Generic filtering: filter a list of ids using ignore filters
# Implements the two-step pattern:
#   1. Apply ignore filter to selected set to get final set
# Args:
#   $1: input_ids_ref - Name of array variable with ids to filter
#   $2: ignore_filter - The ignore filter, expanded using expand_filter_string
# Returns:
#   Filtered ids, one per line
# Usage:
#   input_ids=("rust-v0.56" "rust-v0.55" "go-v0.45")
#   ignore_filter="v0.56|v0.45"
#   Returns: rust-v0.55
filter() {
  local -n input_ids_ref=$1
  local ignore_filter=$2
  local selected=("${input_ids_ref[@]}")

  # Apply IGNORE filter
  local final=()
  if [ -z "$ignore_filter" ]; then
    # No ignore filter, include all selected ids
    final=("${selected[@]}")
  else
    for id in "${selected[@]}"; do
      if ! filter_matches "${id}" "${ignore_filter}"; then
        # Include the ID that does NOT match any of the ignore filter substrings
        final+=("${id}")
      fi
    done
  fi

  # Step 3: Return the filtered ids, one per line
  printf '%s\n' "${final[@]}"
}
