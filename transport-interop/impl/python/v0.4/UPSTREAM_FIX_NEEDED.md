# Upstream Fix Needed: multiaddr vs py-libp2p multihash Conflict

## The Problem

When installing `py-libp2p` in a fresh environment (like Docker), there's a dependency conflict:

1. **`py-libp2p`** requires `pymultihash>=0.8.2` (provides `multihash.Func` and `multihash.digest()`)
2. **`multiaddr 0.1.0`** (dependency of `py-libp2p`) requires `py-multihash 2.0.1` (provides `multihash.encode()` and `multihash.decode()`, but NOT `Func` or `digest()`)
3. Both packages provide a Python module named `multihash`, causing a namespace collision
4. Python imports the first one it finds (usually `py-multihash`), which doesn't have the APIs that `py-libp2p` needs
5. Result: `AttributeError: module 'multihash' has no attribute 'Func'`

## Why This Doesn't Manifest in py-libp2p Development

**Important**: This conflict **does exist**, but it doesn't manifest in `py-libp2p`'s development environment because:

- Developers' venvs have `multiaddr 0.0.12` installed (NOT `0.1.0`)
- `multiaddr 0.0.12` does **NOT** depend on `py-multihash`
- So only `pymultihash` is installed, no conflict

The conflict only appears when:
- Installing fresh dependencies in a clean environment
- `pip` resolves to `multiaddr 0.1.0` (the latest version)
- Which pulls in `py-multihash 2.0.1` as a dependency

## What Needs to Be Fixed

### Option 1: Fix in `multiaddr` (Recommended)

**Problem**: `multiaddr 0.1.0` added `py-multihash` as a dependency, but this conflicts with `pymultihash` that `py-libp2p` needs.

**Solution**: `multiaddr` should either:
1. **Use `pymultihash` instead of `py-multihash`** (if it needs multihash functionality)
   - This would align with what `py-libp2p` already uses
   - Both packages would use the same multihash implementation
   
2. **Remove the `py-multihash` dependency** (if it doesn't actually need multihash functionality)
   - Check if `multiaddr` actually uses multihash APIs
   - If not, remove the dependency to avoid the conflict

3. **Make the dependency optional or conditional**
   - Only require `py-multihash` if actually needed
   - Or provide a way to use either package

**Action**: File an issue/PR with the `multiaddr` maintainers to:
- Investigate why `py-multihash` was added as a dependency in `0.1.0`
- Determine if `multiaddr` actually needs multihash functionality
- If yes, switch to `pymultihash` to align with `py-libp2p`
- If no, remove the dependency

### Option 2: Fix in `py-libp2p`

**Problem**: `py-libp2p` uses `multihash.Func` and `multihash.digest()` APIs that only exist in `pymultihash`, not in `py-multihash`.

**Solution**: `py-libp2p` could update its code to use `py-multihash`'s API instead:
- Replace `multihash.Func.sha2_256` with `multihash.constants.HASH_CODES["sha2-256"]`
- Replace `multihash.digest()` with a function using `multihash.encode()` and `hashlib`
- Update all code that uses these APIs

**Trade-offs**:
- ✅ Would work with `multiaddr 0.1.0`'s dependency
- ❌ Requires significant code changes in `py-libp2p`
- ❌ `py-multihash` might not have all the features `pymultihash` provides
- ❌ Other projects might depend on `py-libp2p` using `pymultihash`

**Action**: This is less ideal because:
- `pymultihash` is already working well for `py-libp2p`
- Changing would require extensive refactoring
- The conflict is caused by `multiaddr` adding a new dependency, not by `py-libp2p`

### Option 3: Pin `multiaddr` Version in `py-libp2p`

**Problem**: `py-libp2p` specifies `multiaddr>=0.0.11`, which allows `0.1.0` to be installed.

**Solution**: Pin `multiaddr` to `>=0.0.11,<0.1.0` in `py-libp2p`'s `pyproject.toml`:
```toml
dependencies = [
    "multiaddr>=0.0.11,<0.1.0",  # Pin to avoid py-multihash conflict
    ...
]
```

**Trade-offs**:
- ✅ Quick fix, no code changes needed
- ✅ Prevents the conflict from occurring
- ❌ Blocks `multiaddr` updates (might miss bug fixes or features)
- ❌ Not a long-term solution
- ❌ Doesn't fix the root cause

**Action**: This is a temporary workaround, not a proper fix.

## Recommended Approach

**Best solution**: **Option 1 - Fix in `multiaddr`**

1. **Investigate**: Check if `multiaddr 0.1.0` actually needs `py-multihash`
   - Review the `multiaddr` codebase
   - Check if it uses any multihash APIs
   - Determine why `py-multihash` was added as a dependency

2. **If multihash is needed**: Switch `multiaddr` to use `pymultihash` instead
   - Update `multiaddr`'s dependencies to use `pymultihash>=0.8.2`
   - Update `multiaddr`'s code to use `pymultihash` APIs
   - This aligns with what `py-libp2p` already uses

3. **If multihash is not needed**: Remove the `py-multihash` dependency
   - Remove it from `multiaddr`'s `pyproject.toml`
   - Verify `multiaddr` still works correctly
   - Release a new version without the dependency

## Current Workaround

Until the upstream fix is implemented, the Docker build uses a workaround:

```dockerfile
RUN pip install --no-cache-dir -e . && \
    pip uninstall -y py-multihash && \
    pip install --no-cache-dir --force-reinstall pymultihash>=0.8.2
```

This ensures only `pymultihash` is installed, avoiding the conflict.

## Verification

To verify the fix works:

1. **After `multiaddr` is fixed**:
   ```bash
   pip install multiaddr  # Should not install py-multihash
   pip install py-libp2p  # Should work without conflicts
   python -c "from libp2p.peer.id import ID; print('OK')"
   ```

2. **Check installed packages**:
   ```bash
   pip list | grep multihash
   # Should only show: pymultihash 0.8.2
   # Should NOT show: py-multihash
   ```

## Timeline

- **Current**: Workaround in Docker build
- **Short-term**: Pin `multiaddr` version in `py-libp2p` if needed
- **Long-term**: Fix in `multiaddr` to remove or change the dependency

## References

- `multiaddr` repository: https://github.com/multiformats/py-multiaddr
- `py-libp2p` repository: https://github.com/libp2p/py-libp2p
- `pymultihash` repository: https://github.com/ivilata/pymultihash
- `py-multihash` repository: https://github.com/multiformats/py-multihash

## Summary

The conflict exists because `multiaddr 0.1.0` added `py-multihash` as a dependency, which conflicts with `pymultihash` that `py-libp2p` needs. The fix should be in `multiaddr`:
- Either switch to `pymultihash` (if multihash is needed)
- Or remove the dependency (if multihash is not needed)

This is a real issue that manifests in fresh installs, even though it doesn't appear in existing development environments that have `multiaddr 0.0.12` installed.

