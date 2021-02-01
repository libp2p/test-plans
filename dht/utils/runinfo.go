package utils

import (
	"github.com/testground/sdk-go/network"
	"github.com/testground/sdk-go/runtime"
	"github.com/testground/sdk-go/sync"
)

type RunInfo struct {
	RunEnv    *runtime.RunEnv
	Client    *sync.DefaultClient
	NetClient *network.Client

	Groups          []string
	GroupProperties map[string]*GroupInfo
}
