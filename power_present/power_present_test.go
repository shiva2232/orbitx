package main

import (
    "testing"
)

func TestEncodeDecodeMessage(t *testing.T) {
    service := NewPowerPresentService("session-1", "peer-1")
    payload := map[string]interface{}{
        "type": "INPUT_TOUCH_DOWN",
        "x": 0.5,
        "y": 0.5,
    }

    encoded, err := service.EncodeMessage("INPUT_TOUCH_DOWN", payload)
    if err != nil {
        t.Fatalf("EncodeMessage failed: %v", err)
    }

    decoded, err := service.DecodeMessage(encoded)
    if err != nil {
        t.Fatalf("DecodeMessage failed: %v", err)
    }

    if decoded.Type != "INPUT_TOUCH_DOWN" {
        t.Fatalf("unexpected decoded type: %s", decoded.Type)
    }

    if decoded.SessionId != "session-1" {
        t.Fatalf("unexpected session id: %s", decoded.SessionId)
    }
}
