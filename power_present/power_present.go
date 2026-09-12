package main

import (
    "encoding/json"
    "log"
)

type MessageType string

type MessageEnvelope struct {
    Version   int         `json:"version"`
    SessionId string      `json:"sessionId"`
    PeerId    string      `json:"peerId"`
    Sequence  int         `json:"sequence"`
    Type      MessageType `json:"type"`
    Payload   json.RawMessage `json:"payload"`
}

type PowerPresentService struct {
    sessionId string
    peerId    string
}

func NewPowerPresentService(sessionId, peerId string) *PowerPresentService {
    return &PowerPresentService{sessionId: sessionId, peerId: peerId}
}

func (s *PowerPresentService) EncodeMessage(msgType MessageType, payload interface{}) ([]byte, error) {
    payloadData, err := json.Marshal(payload)
    if err != nil {
        return nil, err
    }
    envelope := MessageEnvelope{
        Version:   1,
        SessionId: s.sessionId,
        PeerId:    s.peerId,
        Sequence:  0,
        Type:      msgType,
        Payload:   payloadData,
    }
    return json.Marshal(envelope)
}

func (s *PowerPresentService) DecodeMessage(data []byte) (*MessageEnvelope, error) {
    var envelope MessageEnvelope
    err := json.Unmarshal(data, &envelope)
    if err != nil {
        return nil, err
    }
    return &envelope, nil
}

func (s *PowerPresentService) Log(msg string) {
    log.Printf("[PowerPresent] %s", msg)
}
