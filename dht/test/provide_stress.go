package test

import (
	"fmt"

	"github.com/testground/sdk-go/runtime"
)

// TODO this entire test needs to be revisited.
// ProvideStress implements the Provide Stress test case
func ProvideStress(runenv *runtime.RunEnv) error {
	// 	// Test Parameters
	// 	var (
	// 		timeout     = time.Duration(runenv.IntParamD("timeout_secs", 60)) * time.Second
	// 		randomWalk  = runenv.BooleanParamD("random_walk", false)
	// 		bucketSize  = runenv.IntParamD("bucket_size", 20)
	// 		autoRefresh = runenv.BooleanParamD("auto_refresh", true)
	// 		nProvides   = runenv.IntParamD("n_provides", 10)
	// 		iProvides   = time.Duration(runenv.IntParamD("i-provides", 1)) * time.Second
	// 	)

	// 	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	// 	defer cancel()

	// 	watcher, writer := sync.MustWatcherWriter(runenv)
	// 	defer watcher.Close()
	// 	defer writer.Close()

	// 	_, dht, _, err := SetUp(ctx, runenv, timeout, randomWalk, bucketSize, autoRefresh, watcher, writer)
	// 	if err != nil {
	// 		runenv.Abort(err)
	// 		return
	// 	}

	// 	defer TearDown(ctx, runenv, watcher, writer)

	// 	/// --- Act I
	// 	// Each node calls Provide for `i-provides` until it reaches a total of `n-provides`

	// 	var (
	// 		seed    = 0
	// 		counter = 0
	// 	)

	// Loop:
	// 	for {
	// 		select {
	// 		case <-time.After(iProvides):
	// 			v := fmt.Sprintf("%d -- something random", seed)
	// 			mhv := ipfsUtil.Hash([]byte(v))
	// 			cidToPublish := cid.NewCidV0(mhv)
	// 			err := dht.Provide(ctx, cidToPublish, true)
	// 			if err != nil {
	// 				runenv.Abort(fmt.Errorf("Failed on .Provide - %w", err))
	// 				return
	// 			}
	// 			runenv.RecordMessage("Provided a CID")

	// 			counter++
	// 			if counter == nProvides {
	// 				break Loop
	// 			}
	// 		case <-ctx.Done():
	// 			runenv.Abort(fmt.Errorf("Context closed before ending the test"))
	// 			return
	// 		}
	// 	}

	// 	runenv.RecordMessage("Provided all scheduled CIDs")

	// 	runenv.OK()
	return fmt.Errorf("unimplemented")
}
