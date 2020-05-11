package main

import (
	"errors"
	"fmt"

	"github.com/testground/sdk-go/runtime"
)

func main() {
	runtime.Invoke(run)
}

// Pick a different example function to run
// depending on the name of the test case.
func run(runenv *runtime.RunEnv) error {
	switch c := runenv.TestCase; c {
	case "evaluate":
		return RunSimulation(runenv)
	default:
		msg := fmt.Sprintf("Unknown Testcase %s", c)
		return errors.New(msg)
	}
}
