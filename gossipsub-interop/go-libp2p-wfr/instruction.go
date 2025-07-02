package main

import (
	"encoding/json"
	"fmt"

	pubsub "github.com/libp2p/go-libp2p-pubsub"
)

// ScriptInstruction is an interface that represents any instruction in the script
type ScriptInstruction interface {
	isInstruction()
}

// ConnectInstruction represents a connect instruction in the script
type ConnectInstruction struct {
	Type      string `json:"type"`
	ConnectTo []int  `json:"connectTo"`
}

// isInstruction implements the ScriptInstruction interface
func (ConnectInstruction) isInstruction() {}

// IfNodeIDEqualsInstruction represents a conditional instruction based on node ID
type IfNodeIDEqualsInstruction struct {
	Type        string            `json:"type"`
	NodeID      int               `json:"nodeID"`
	Instruction ScriptInstruction `json:"instruction"`
}

// isInstruction implements the ScriptInstruction interface
func (IfNodeIDEqualsInstruction) isInstruction() {}

// WaitUntilInstruction represents a wait until instruction in the script
type WaitUntilInstruction struct {
	Type           string `json:"type"`
	ElapsedSeconds int    `json:"elapsedSeconds"`
}

// isInstruction implements the ScriptInstruction interface
func (WaitUntilInstruction) isInstruction() {}

// PublishInstruction represents a publish instruction in the script
type PublishInstruction struct {
	Type             string `json:"type"`
	MessageID        int    `json:"messageID"`
	MessageSizeBytes int    `json:"messageSizeBytes"`
	TopicID          string `json:"topicID"`
}

// isInstruction implements the ScriptInstruction interface
func (PublishInstruction) isInstruction() {}

// SubscribeToTopicInstruction represents a subscribe instruction in the script
type SubscribeToTopicInstruction struct {
	Type    string `json:"type"`
	TopicID string `json:"topicID"`
}

// isInstruction implements the ScriptInstruction interface
func (SubscribeToTopicInstruction) isInstruction() {}

// InitGossipSubInstruction represents an instruction to initialize GossipSub with specific parameters
type InitGossipSubInstruction struct {
	Type            string                 `json:"type"`
	GossipSubParams pubsub.GossipSubParams `json:"gossipSubParams"`
}

// isInstruction implements the ScriptInstruction interface
func (InitGossipSubInstruction) isInstruction() {}

// UnmarshalScriptInstruction unmarshals a JSON object into the appropriate ScriptInstruction type
func UnmarshalScriptInstruction(data []byte) (ScriptInstruction, error) {
	// Unmarshal just the type field to determine which concrete type to use
	var temp struct {
		Type string `json:"type"`
	}
	if err := json.Unmarshal(data, &temp); err != nil {
		return nil, err
	}

	// Unmarshal to the appropriate concrete type based on the instruction type
	switch temp.Type {
	case "connect":
		var instruction ConnectInstruction
		if err := json.Unmarshal(data, &instruction); err != nil {
			return nil, err
		}
		return instruction, nil

	case "ifNodeIDEquals":
		var tempInstruction struct {
			Type        string          `json:"type"`
			NodeID      int             `json:"nodeID"`
			Instruction json.RawMessage `json:"instruction"`
		}
		if err := json.Unmarshal(data, &tempInstruction); err != nil {
			return nil, err
		}

		// Recursively unmarshal the nested instruction
		nestedInstruction, err := UnmarshalScriptInstruction(tempInstruction.Instruction)
		if err != nil {
			return nil, err
		}

		return IfNodeIDEqualsInstruction{
			Type:        tempInstruction.Type,
			NodeID:      tempInstruction.NodeID,
			Instruction: nestedInstruction,
		}, nil

	case "waitUntil":
		var instruction WaitUntilInstruction
		if err := json.Unmarshal(data, &instruction); err != nil {
			return nil, err
		}
		return instruction, nil

	case "publish":
		var instruction PublishInstruction
		if err := json.Unmarshal(data, &instruction); err != nil {
			return nil, err
		}
		return instruction, nil

	case "subscribeToTopic":
		var instruction SubscribeToTopicInstruction
		if err := json.Unmarshal(data, &instruction); err != nil {
			return nil, err
		}
		return instruction, nil

	case "initGossipSub":
		var tempInstruction struct {
			Type            string          `json:"type"`
			GossipSubParams json.RawMessage `json:"gossipSubParams"`
		}
		if err := json.Unmarshal(data, &tempInstruction); err != nil {
			return nil, err
		}

		// Start with default parameters
		params := pubsub.DefaultGossipSubParams()

		// Only override values that are specified in the JSON
		if err := json.Unmarshal(tempInstruction.GossipSubParams, &params); err != nil {
			return nil, err
		}
		return InitGossipSubInstruction{
			Type:            tempInstruction.Type,
			GossipSubParams: params,
		}, nil

	default:
		return nil, fmt.Errorf("unknown instruction type: %s", temp.Type)
	}
}

// ScriptInstructions is a slice of ScriptInstruction that can be unmarshaled from JSON
type ScriptInstructions []ScriptInstruction

// UnmarshalJSON implements json.Unmarshaler for ScriptInstructions
func (si *ScriptInstructions) UnmarshalJSON(data []byte) error {
	var rawInstructions []json.RawMessage
	if err := json.Unmarshal(data, &rawInstructions); err != nil {
		return err
	}

	instructions := make([]ScriptInstruction, len(rawInstructions))
	for i, raw := range rawInstructions {
		instruction, err := UnmarshalScriptInstruction(raw)
		if err != nil {
			return err
		}
		instructions[i] = instruction
	}

	*si = instructions
	return nil
}
