package main

import (
	"encoding/json"
	"fmt"
	
	pubsub "github.com/libp2p/go-libp2p-pubsub"
)

// ScriptAction is an interface that represents any action in the script
type ScriptAction interface {
	isAction()
}

// ConnectAction represents a connect action in the script
type ConnectAction struct {
	Type      string `json:"type"`
	ConnectTo []int  `json:"connectTo"`
}

// isAction implements the ScriptAction interface
func (ConnectAction) isAction() {}

// IfNodeIDEqualsAction represents a conditional action based on node ID
type IfNodeIDEqualsAction struct {
	Type   string       `json:"type"`
	NodeID int          `json:"nodeID"`
	Action ScriptAction `json:"action"`
}

// isAction implements the ScriptAction interface
func (IfNodeIDEqualsAction) isAction() {}

// WaitUntilAction represents a wait until action in the script
type WaitUntilAction struct {
	Type           string `json:"type"`
	ElapsedSeconds int    `json:"elapsedSeconds"`
}

// isAction implements the ScriptAction interface
func (WaitUntilAction) isAction() {}

// PublishAction represents a publish action in the script
type PublishAction struct {
	Type             string `json:"type"`
	MessageID        int    `json:"messageID"`
	MessageSizeBytes int    `json:"messageSizeBytes"`
	TopicID          string `json:"topicID"`
}

// isAction implements the ScriptAction interface
func (PublishAction) isAction() {}

// SubscribeToTopicAction represents a subscribe action in the script
type SubscribeToTopicAction struct {
	Type    string `json:"type"`
	TopicID string `json:"topicID"`
}

// isAction implements the ScriptAction interface
func (SubscribeToTopicAction) isAction() {}

// InitGossipSubAction represents an action to initialize GossipSub with specific parameters
type InitGossipSubAction struct {
	Type            string               `json:"type"`
	GossipSubParams pubsub.GossipSubParams `json:"gossipSubParams"`
}

// isAction implements the ScriptAction interface
func (InitGossipSubAction) isAction() {}

// UnmarshalScriptAction unmarshals a JSON object into the appropriate ScriptAction type
func UnmarshalScriptAction(data []byte) (ScriptAction, error) {
	// Unmarshal just the type field to determine which concrete type to use
	var temp struct {
		Type string `json:"type"`
	}
	if err := json.Unmarshal(data, &temp); err != nil {
		return nil, err
	}

	// Unmarshal to the appropriate concrete type based on the action type
	switch temp.Type {
	case "connect":
		var action ConnectAction
		if err := json.Unmarshal(data, &action); err != nil {
			return nil, err
		}
		return action, nil

	case "ifNodeIDEquals":
		// Handle the nested action by first getting the raw action field
		var tempAction struct {
			Type   string          `json:"type"`
			NodeID int             `json:"nodeID"`
			Action json.RawMessage `json:"action"`
		}
		if err := json.Unmarshal(data, &tempAction); err != nil {
			return nil, err
		}

		// Recursively unmarshal the nested action
		nestedAction, err := UnmarshalScriptAction(tempAction.Action)
		if err != nil {
			return nil, err
		}

		return IfNodeIDEqualsAction{
			Type:   tempAction.Type,
			NodeID: tempAction.NodeID,
			Action: nestedAction,
		}, nil

	case "waitUntil":
		var action WaitUntilAction
		if err := json.Unmarshal(data, &action); err != nil {
			return nil, err
		}
		return action, nil

	case "publish":
		var action PublishAction
		if err := json.Unmarshal(data, &action); err != nil {
			return nil, err
		}
		return action, nil
		
	case "subscribeToTopic":
		var action SubscribeToTopicAction
		if err := json.Unmarshal(data, &action); err != nil {
			return nil, err
		}
		return action, nil
		
	case "initGossipSub":
		var tempAction struct {
			Type            string          `json:"type"`
			GossipSubParams json.RawMessage `json:"gossipSubParams"`
		}
		if err := json.Unmarshal(data, &tempAction); err != nil {
			return nil, err
		}
		
		// Start with default parameters
		params := pubsub.DefaultGossipSubParams()
		
		// Only override values that are specified in the JSON
		if err := json.Unmarshal(tempAction.GossipSubParams, &params); err != nil {
			return nil, err
		}
		
		return InitGossipSubAction{
			Type:            tempAction.Type,
			GossipSubParams: params,
		}, nil

	default:
		return nil, fmt.Errorf("unknown action type: %s", temp.Type)
	}
}

// ScriptActions is a slice of ScriptAction that can be unmarshaled from JSON
type ScriptActions []ScriptAction

// UnmarshalJSON implements json.Unmarshaler for ScriptActions
func (sa *ScriptActions) UnmarshalJSON(data []byte) error {
	var rawActions []json.RawMessage
	if err := json.Unmarshal(data, &rawActions); err != nil {
		return err
	}

	actions := make([]ScriptAction, len(rawActions))
	for i, raw := range rawActions {
		action, err := UnmarshalScriptAction(raw)
		if err != nil {
			return err
		}
		actions[i] = action
	}

	*sa = actions
	return nil
}
