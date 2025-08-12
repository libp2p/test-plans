import json
import os
import glob

def main():
    """
    Verify Extensions Interop

    This script verifies the interoperability of extensions in the gossipsub
    protocol. It checks that the first node in latest-sim/ emits the following
    logs to stdout. (time does not matter):

    ```
    {"time":"2000-01-01T00:00:00.98055772Z","level":"INFO","msg":"Received RPC","service":"gossipsub","rpc":{"testExtension":{}}}
    {"time":"2000-01-01T00:00:00.98053614Z","level":"INFO","msg":"Send RPC","service":"gossipsub","rpc":{"testExtension":{}},"to":"12D3KooWPjceQrSwdWXPyLLeABRXmuqt69Rg3sBYbU1Nft9HyQ6X"}
    ```
    """

    stdout_pattern = os.path.join(os.path.dirname(__file__), "latest-sim", "hosts", "node0", "*.stdout")
    stdout_files = glob.glob(stdout_pattern)
    if not stdout_files:
        raise FileNotFoundError(f"No stdout files found matching pattern: {stdout_pattern}")

    with open(stdout_files[0], 'r') as f:
        log = f.read()

    sent_test_extension = False
    received_test_extension = False

    for line in log.strip().split("\n"):
        entry = json.loads(line)
        if entry.get("msg") == "Send RPC":
            if "testExtension" in entry.get("rpc", {}):
                sent_test_extension = True
        if entry.get("msg") == "Received RPC":
            if "testExtension" in entry.get("rpc", {}):
                received_test_extension = True

    if sent_test_extension and received_test_extension:
        print("SUCCESS: Both testExtension sent and received")
    else:
        print("FAILURE: Missing testExtension messages")
        exit(1)

if __name__ == "__main__":
    main()
