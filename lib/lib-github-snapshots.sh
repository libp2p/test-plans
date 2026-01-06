#!/bin/bash
# GitHub snapshot handling library with git submodule support
# Handles both ZIP snapshots and git clones for implementations requiring submodules

# Get list of required GitHub sources from images.yaml
# Returns: TSV with commit, repo, requiresSubmodules flag
# Format: commit<TAB>repo<TAB>requiresSubmodules
get_required_github_sources() {
    if [ ! -f images.yaml ]; then
        echo "✗ Error: images.yaml not found" >&2
        return 1
    fi

    yq eval '.implementations[] |
        select(.source.type == "github") |
        .source.commit + "\t" + .source.repo + "\t" + (.source.requiresSubmodules // false)' \
        images.yaml
}

# Get unique commits from implementations (for both zip and git)
# Returns: List of unique commits, one per line
get_unique_github_commits() {
    if [ ! -f images.yaml ]; then
        return 1
    fi

    yq eval '.implementations[] |
        select(.source.type == "github") |
        .source.commit' images.yaml | sort -u
}

# Validate that all required GitHub sources are cached
# Args:
#   $1: cache_dir - Cache directory to check
# Returns: 0 if all present, 1 if any missing
validate_github_sources_cached() {
    local cache_dir="$1"

    local missing=false
    local missing_count=0

    while IFS=$'\t' read -r commit repo requires_submodules; do
        local repo_name=$(basename "$repo")

        if [ "$requires_submodules" = "true" ]; then
            # Check for git clone
            local git_dir="$cache_dir/git-repo/${repo_name}-${commit}"
            if [ ! -d "$git_dir" ]; then
                echo "✗ Missing git clone: ${repo_name}-${commit:0:8} (requires submodules)" >&2
                missing=true
                missing_count=$((missing_count + 1))
            fi
        else
            # Check for zip snapshot
            if [ ! -f "$cache_dir/snapshots/${commit}.zip" ]; then
                echo "✗ Missing ZIP snapshot: ${commit:0:8}" >&2
                missing=true
                missing_count=$((missing_count + 1))
            fi
        fi
    done < <(get_required_github_sources)

    if [ "$missing" = true ]; then
        echo "✗ Total missing sources: $missing_count" >&2
        return 1
    fi

    return 0
}

# Copy GitHub sources to snapshot directory
# Handles both ZIP snapshots and git clones with submodules
# Args:
#   $1: snapshot_dir - Target snapshot directory
#   $2: cache_dir - Source cache directory
# Returns: 0 on success, 1 if errors
copy_github_sources_to_snapshot() {
    local snapshot_dir="$1"
    local cache_dir="$2"
    indent

    mkdir -p "$snapshot_dir/snapshots"
    mkdir -p "$snapshot_dir/git-repos"

    local copied_zips=0
    local copied_git=0
    local missing=0

    while IFS=$'\t' read -r commit repo requires_submodules; do
        local repo_name=$(basename "$repo")

        if [ "$requires_submodules" = "true" ]; then
            # Copy git clone (includes submodules)
            local git_dir="$cache_dir/git-repo/${repo_name}-${commit}"
            if [ -d "$git_dir" ]; then
                cp -r "$git_dir" "$snapshot_dir/git-repo/"
                copied_git=$((copied_git + 1))
            else
                print_error "Warning: Missing git clone for $repo_name (commit: ${commit:0:8})" >&2
                missing=$((missing + 1))
            fi
        else
            # Copy ZIP snapshot
            if [ -f "$cache_dir/snapshots/${commit}.zip" ]; then
                cp "$cache_dir/snapshots/${commit}.zip" "$snapshot_dir/snapshots/"
                copied_zips=$((copied_zips + 1))
            else
                print_error "Warning: Missing ZIP snapshot for commit ${commit:0:8}" >&2
                missing=$((missing + 1))
            fi
        fi
    done < <(get_required_github_sources)

    # Report results
    if [ $copied_zips -gt 0 ]; then
        print_success "Copied $copied_zips ZIP snapshots"
    fi

    if [ $copied_git -gt 0 ]; then
        print_success "Copied $copied_git git clones (with submodules)"
    fi

    if [ $missing -gt 0 ]; then
        print_error "Warning: $missing sources missing from cache" >&2
        unindent
        return 1
    fi

    unindent
    return 0
}

# Prepare git clones for building by making them available in cache
# Args:
#   $1: snapshot_dir - Snapshot directory containing git-repos/
#   $2: cache_dir - Target cache directory
# Returns: 0 on success
prepare_git_clones_for_build() {
    local snapshot_dir="$1"
    local cache_dir="$2"

    # Check if git-repos/ exists in snapshot
    if [ ! -d "$snapshot_dir/git-repos" ]; then
        return 0  # No git clones, nothing to do
    fi

    local git_dirs=$(ls -d "$snapshot_dir/git-repo/"*/ 2>/dev/null || echo "")
    if [ -z "$git_dirs" ]; then
        return 0  # Empty directory
    fi

    # Create cache git-repos directory
    mkdir -p "$cache_dir/git-repos"

    local copied=0
    for git_dir in $git_dirs; do
        local dir_name=$(basename "$git_dir")

        # Only copy if not already in cache
        if [ ! -d "$cache_dir/git-repo/$dir_name" ]; then
            cp -r "$git_dir" "$cache_dir/git-repo/"
            copied=$((copied + 1))
        fi
    done

    if [ $copied -gt 0 ]; then
        echo "  ✓ Prepared $copied git clones for building"
    fi

    return 0
}

# Prepare ZIP snapshots for building
# Args:
#   $1: snapshot_dir - Snapshot directory containing snapshots/
#   $2: cache_dir - Target cache directory
# Returns: 0 on success
prepare_zip_snapshots_for_build() {
    local snapshot_dir="$1"
    local cache_dir="$2"

    # Check if snapshots/ exists
    if [ ! -d "$snapshot_dir/snapshots" ]; then
        return 0
    fi

    local zip_files=$(ls "$snapshot_dir/snapshots/"*.zip 2>/dev/null || echo "")
    if [ -z "$zip_files" ]; then
        return 0
    fi

    # Create cache snapshots directory
    mkdir -p "$cache_dir/snapshots"

    local copied=0
    for zip_file in $zip_files; do
        local zip_name=$(basename "$zip_file")

        # Only copy if not already in cache
        if [ ! -f "$cache_dir/snapshots/$zip_name" ]; then
            cp "$zip_file" "$cache_dir/snapshots/"
            copied=$((copied + 1))
        fi
    done

    if [ $copied -gt 0 ]; then
        echo "  ✓ Prepared $copied ZIP snapshots for building"
    fi

    return 0
}

# Validate snapshot has all required GitHub sources
# Args:
#   $1: snapshot_dir - Snapshot directory to validate
# Returns: 0 if all present, 1 if missing
validate_snapshot_github_sources() {
    local snapshot_dir="$1"

    local missing=false
    local expected_zips=0
    local expected_gits=0
    local found_zips=0
    local found_gits=0

    while IFS=$'\t' read -r commit repo requires_submodules; do
        local repo_name=$(basename "$repo")

        if [ "$requires_submodules" = "true" ]; then
            expected_gits=$((expected_gits + 1))
            # Check for git clone in snapshot
            if [ -d "$snapshot_dir/git-repo/${repo_name}-${commit}" ]; then
                found_gits=$((found_gits + 1))
            else
                echo "  ✗ Missing git clone in snapshot: ${repo_name}-${commit:0:8}" >&2
                missing=true
            fi
        else
            expected_zips=$((expected_zips + 1))
            # Check for ZIP in snapshot
            if [ -f "$snapshot_dir/snapshots/${commit}.zip" ]; then
                found_zips=$((found_zips + 1))
            else
                echo "  ✗ Missing ZIP in snapshot: ${commit:0:8}" >&2
                missing=true
            fi
        fi
    done < <(cd "$snapshot_dir" && get_required_github_sources)

    if [ "$missing" = true ]; then
        echo "  ✗ Snapshot incomplete: found $found_zips/$expected_zips ZIPs, $found_gits/$expected_gits git clones" >&2
        return 1
    fi

    echo "  ✓ Snapshot has all sources: $found_zips ZIPs, $found_gits git clones"
    return 0
}

# Download missing GitHub sources to cache
# Args:
#   $1: cache_dir - Cache directory
#   $2: source_type - Type to download: "zip", "git", or "all"
# Returns: 0 on success, 1 if errors
download_missing_github_sources() {
    local cache_dir="$1"
    local source_type="${2:-all}"

    local downloaded_zips=0
    local downloaded_gits=0
    local failed=0

    while IFS=$'\t' read -r commit repo requires_submodules; do
        local repo_name=$(basename "$repo")

        if [ "$requires_submodules" = "true" ]; then
            # Handle git clone
            if [ "$source_type" = "all" ] || [ "$source_type" = "git" ]; then
                local git_dir="$cache_dir/git-repo/${repo_name}-${commit}"
                if [ ! -d "$git_dir" ]; then
                    echo "  → Cloning $repo (commit: ${commit:0:8}) with submodules..."

                    # Use the existing clone_github_repo_with_submodules from lib-image-building.sh
                    # This requires lib-image-building.sh to be sourced
                    if type clone_github_repo_with_submodules &>/dev/null; then
                        if clone_github_repo_with_submodules "$repo" "$commit" "$cache_dir" >/dev/null 2>&1; then
                            downloaded_gits=$((downloaded_gits + 1))
                        else
                            echo "  ✗ Failed to clone $repo" >&2
                            failed=$((failed + 1))
                        fi
                    else
                        echo "  ✗ clone_github_repo_with_submodules not available (source lib-image-building.sh)" >&2
                        failed=$((failed + 1))
                    fi
                fi
            fi
        else
            # Handle ZIP download
            if [ "$source_type" = "all" ] || [ "$source_type" = "zip" ]; then
                if [ ! -f "$cache_dir/snapshots/${commit}.zip" ]; then
                    echo "  → Downloading $repo (commit: ${commit:0:8}) as ZIP..."

                    # Use the existing download_github_snapshot from lib-image-building.sh
                    if type download_github_snapshot &>/dev/null; then
                        if download_github_snapshot "$repo" "$commit" "$cache_dir" >/dev/null 2>&1; then
                            downloaded_zips=$((downloaded_zips + 1))
                        else
                            echo "  ✗ Failed to download ZIP for ${commit:0:8}" >&2
                            failed=$((failed + 1))
                        fi
                    else
                        echo "  ✗ download_github_snapshot not available (source lib-image-building.sh)" >&2
                        failed=$((failed + 1))
                    fi
                fi
            fi
        fi
    done < <(get_required_github_sources)

    # Report results
    if [ $downloaded_zips -gt 0 ]; then
        echo "  ✓ Downloaded $downloaded_zips ZIP snapshots"
    fi

    if [ $downloaded_gits -gt 0 ]; then
        echo "  ✓ Cloned $downloaded_gits repositories with submodules"
    fi

    if [ $failed -gt 0 ]; then
        echo "  ✗ Failed to download $failed sources" >&2
        return 1
    fi

    return 0
}

# Count GitHub sources by type
# Args:
#   $1: snapshot_dir - Snapshot directory to count
# Returns: Prints counts to stdout
count_github_sources_in_snapshot() {
    local snapshot_dir="$1"

    local zip_count=0
    local git_count=0

    if [ -d "$snapshot_dir/snapshots" ]; then
        zip_count=$(ls -1 "$snapshot_dir/snapshots/"*.zip 2>/dev/null | wc -l)
    fi

    if [ -d "$snapshot_dir/git-repos" ]; then
        git_count=$(ls -d "$snapshot_dir/git-repo/"*/ 2>/dev/null | wc -l)
    fi

    echo "zip:$zip_count git:$git_count"
}

# Check if implementation requires git clone (has submodules)
# Args:
#   $1: impl_id - Implementation ID to check
# Returns: 0 if requires git, 1 if ZIP is sufficient
impl_requires_git_clone() {
    local impl_id="$1"

    local requires=$(yq eval ".implementations[] |
        select(.id == \"$impl_id\") |
        .source.requiresSubmodules // false" images.yaml)

    [ "$requires" = "true" ]
}

# Get source type for implementation
# Args:
#   $1: impl_id - Implementation ID
# Returns: "git" or "zip" or "local" or "browser"
get_impl_source_type() {
    local impl_id="$1"

    local source_type=$(yq eval ".implementations[] |
        select(.id == \"$impl_id\") |
        .source.type" images.yaml)

    if [ "$source_type" = "github" ]; then
        if impl_requires_git_clone "$impl_id"; then
            echo "git"
        else
            echo "zip"
        fi
    else
        echo "$source_type"
    fi
}

# Verify git clone has submodules initialized
# Args:
#   $1: git_clone_dir - Git clone directory to check
# Returns: 0 if submodules present, 1 if not or not initialized
verify_git_submodules() {
    local git_clone_dir="$1"

    if [ ! -d "$git_clone_dir" ]; then
        return 1
    fi

    # Check if .gitmodules exists
    if [ ! -f "$git_clone_dir/.gitmodules" ]; then
        return 0  # No submodules defined, that's okay
    fi

    # Check if submodules are initialized (look for .git/modules/)
    if [ -d "$git_clone_dir/.git/modules" ]; then
        return 0  # Submodules initialized
    fi

    # Alternative check: see if submodule directories have content
    local submodule_count=$(git -C "$git_clone_dir" config --file .gitmodules --get-regexp path | wc -l)
    if [ $submodule_count -gt 0 ]; then
        # Check if first submodule directory has files
        local first_submodule=$(git -C "$git_clone_dir" config --file .gitmodules --get-regexp path | head -1 | awk '{print $2}')
        if [ -d "$git_clone_dir/$first_submodule" ] && [ "$(ls -A "$git_clone_dir/$first_submodule" 2>/dev/null)" ]; then
            return 0  # Submodule has content
        fi
    fi

    return 1  # Submodules not initialized
}

# List all GitHub sources in a snapshot
# Args:
#   $1: snapshot_dir - Snapshot directory
# Returns: List of sources with type
list_github_sources_in_snapshot() {
    local snapshot_dir="$1"

    echo "ZIP Snapshots:"
    if [ -d "$snapshot_dir/snapshots" ]; then
        ls -1 "$snapshot_dir/snapshots/"*.zip 2>/dev/null | while read -r zip_file; do
            local zip_name=$(basename "$zip_file")
            local commit="${zip_name%.zip}"
            echo "  → ${commit:0:8}.zip"
        done
    fi

    echo ""
    echo "Git Clones (with submodules):"
    if [ -d "$snapshot_dir/git-repos" ]; then
        ls -d "$snapshot_dir/git-repo/"*/ 2>/dev/null | while read -r git_dir; do
            local dir_name=$(basename "$git_dir")
            local has_submodules="no"
            if [ -f "$git_dir/.gitmodules" ]; then
                has_submodules="yes"
            fi
            echo "  → $dir_name (submodules: $has_submodules)"
        done
    fi
}

# Generate source loading shell code for re-run.sh
# This code will be embedded in the generated re-run.sh script
# Args:
#   $1: test_type - Type of test
# Returns: Shell code (via stdout)
generate_source_loading_code() {
    local test_type="$1"

    cat <<'SOURCELOAD'
# Load GitHub sources (both ZIP and git clones with submodules)
load_github_sources() {
    echo "╲ Validating GitHub sources..."
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

    local has_snapshots=false
    local has_git_repos=false

    # Check for ZIP snapshots
    if [ -d snapshots ] && [ "$(ls -A snapshots/*.zip 2>/dev/null)" ]; then
        has_snapshots=true
        local zip_count=$(ls -1 snapshots/*.zip 2>/dev/null | wc -l)
        echo "  ✓ Found $zip_count ZIP snapshots"
    fi

    # Check for git clones
    if [ -d git-repos ] && [ "$(ls -A git-repos 2>/dev/null)" ]; then
        has_git_repos=true
        local git_count=$(ls -d git-repos/*/ 2>/dev/null | wc -l)
        echo "  ✓ Found $git_count git clones (with submodules)"
    fi

    if [ "$has_snapshots" = false ] && [ "$has_git_repos" = false ]; then
        echo "  ⚠ No GitHub sources found in snapshot"
        echo "  → Images must be rebuilt or loaded from docker-images/"
    fi

    # Make sources available to build system
    if [ "$has_git_repos" = true ]; then
        prepare_git_clones_for_build_internal
    fi

    if [ "$has_snapshots" = true ]; then
        prepare_zip_snapshots_for_build_internal
    fi
}

# Internal: Prepare git clones for build system
prepare_git_clones_for_build_internal() {
    mkdir -p "$CACHE_DIR/git-repos"

    local copied=0
    for git_dir in git-repos/*/; do
        [ ! -d "$git_dir" ] && continue
        local dir_name=$(basename "$git_dir")

        if [ ! -d "$CACHE_DIR/git-repo/$dir_name" ]; then
            cp -r "$git_dir" "$CACHE_DIR/git-repo/"
            copied=$((copied + 1))
        fi
    done

    if [ $copied -gt 0 ]; then
        echo "  ✓ Git clones available in cache ($copied prepared)"
    fi
}

# Internal: Prepare ZIP snapshots for build system
prepare_zip_snapshots_for_build_internal() {
    mkdir -p "$CACHE_DIR/snapshots"

    local copied=0
    for zip_file in snapshots/*.zip; do
        [ ! -f "$zip_file" ] && continue
        local zip_name=$(basename "$zip_file")

        if [ ! -f "$CACHE_DIR/snapshots/$zip_name" ]; then
            cp "$zip_file" "$CACHE_DIR/snapshots/"
            copied=$((copied + 1))
        fi
    done

    if [ $copied -gt 0 ]; then
        echo "  ✓ ZIP snapshots available in cache ($copied prepared)"
    fi
}
SOURCELOAD
}

# Get summary statistics for GitHub sources
# Args:
#   $1: cache_dir - Cache directory
# Returns: Summary string
get_github_sources_summary() {
    local cache_dir="$1"

    local zip_cached=0
    local git_cached=0

    if [ -d "$cache_dir/snapshots" ]; then
        zip_cached=$(ls -1 "$cache_dir/snapshots/"*.zip 2>/dev/null | wc -l)
    fi

    if [ -d "$cache_dir/git-repos" ]; then
        git_cached=$(ls -d "$cache_dir/git-repo/"*/ 2>/dev/null | wc -l)
    fi

    echo "Cached: $zip_cached ZIPs, $git_cached git clones"
}

# Clean up empty source directories in snapshot
# Args:
#   $1: snapshot_dir - Snapshot directory
cleanup_empty_source_dirs() {
    local snapshot_dir="$1"

    # Remove empty snapshots/ directory
    if [ -d "$snapshot_dir/snapshots" ] && [ ! "$(ls -A "$snapshot_dir/snapshots" 2>/dev/null)" ]; then
        rmdir "$snapshot_dir/snapshots"
    fi

    # Remove empty git-repos/ directory
    if [ -d "$snapshot_dir/git-repos" ] && [ ! "$(ls -A "$snapshot_dir/git-repos" 2>/dev/null)" ]; then
        rmdir "$snapshot_dir/git-repos"
    fi
}
