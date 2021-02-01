package main

import "github.com/testground/sdk-go/run"

var testCases = map[string]interface{}{
	"evaluate": RunSimulation,
}

func main() {
	run.InvokeMap(testCases)
}
