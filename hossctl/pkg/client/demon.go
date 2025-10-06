package client

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// DemonClient is a client for the Demon platform API
type DemonClient struct {
	baseURL    string
	token      string
	httpClient *http.Client
}

// RitualStartResponse represents the response from starting a ritual
type RitualStartResponse struct {
	RunID  string `json:"runId"`
	Status string `json:"status"`
	Ritual string `json:"ritual"`
}

// RunStatus represents the status of a ritual run
type RunStatus struct {
	RunID     string                 `json:"runId"`
	Status    string                 `json:"status"`
	Ritual    string                 `json:"ritual"`
	CreatedAt string                 `json:"createdAt"`
	UpdatedAt string                 `json:"updatedAt"`
	Envelope  map[string]interface{} `json:"envelope,omitempty"`
}

// NewDemonClient creates a new Demon API client
func NewDemonClient(baseURL, token string) *DemonClient {
	return &DemonClient{
		baseURL: baseURL,
		token:   token,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// StartRitual starts a new ritual execution
func (c *DemonClient) StartRitual(ritualName string, input map[string]interface{}) (string, error) {
	url := fmt.Sprintf("%s/api/v1/rituals/%s/runs", c.baseURL, ritualName)

	requestBody := map[string]interface{}{
		"input": input,
	}

	bodyBytes, err := json.Marshal(requestBody)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(bodyBytes))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if c.token != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.token))
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("API error (status %d): %s", resp.StatusCode, string(body))
	}

	var startResp RitualStartResponse
	if err := json.NewDecoder(resp.Body).Decode(&startResp); err != nil {
		return "", fmt.Errorf("failed to decode response: %w", err)
	}

	return startResp.RunID, nil
}

// GetRunStatus retrieves the status of a ritual run
func (c *DemonClient) GetRunStatus(runID string) (*RunStatus, error) {
	url := fmt.Sprintf("%s/api/v1/runs/%s", c.baseURL, runID)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	if c.token != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.token))
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("API error (status %d): %s", resp.StatusCode, string(body))
	}

	var status RunStatus
	if err := json.NewDecoder(resp.Body).Decode(&status); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &status, nil
}

// GetEnvelope retrieves the result envelope for a completed run
func (c *DemonClient) GetEnvelope(runID string) (map[string]interface{}, error) {
	url := fmt.Sprintf("%s/api/v1/runs/%s/envelope", c.baseURL, runID)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	if c.token != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.token))
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("API error (status %d): %s", resp.StatusCode, string(body))
	}

	var envelope map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&envelope); err != nil {
		return nil, fmt.Errorf("failed to decode envelope: %w", err)
	}

	return envelope, nil
}

// WaitForRitual waits for a ritual run to complete and returns the envelope
func (c *DemonClient) WaitForRitual(runID string, timeout time.Duration) (map[string]interface{}, error) {
	deadline := time.Now().Add(timeout)
	pollInterval := 2 * time.Second

	for time.Now().Before(deadline) {
		status, err := c.GetRunStatus(runID)
		if err != nil {
			return nil, fmt.Errorf("failed to get run status: %w", err)
		}

		switch status.Status {
		case "completed", "success":
			// Fetch envelope
			envelope, err := c.GetEnvelope(runID)
			if err != nil {
				return nil, fmt.Errorf("failed to get envelope: %w", err)
			}
			return envelope, nil

		case "failed", "error":
			// Try to fetch envelope even on failure (may contain error details)
			envelope, err := c.GetEnvelope(runID)
			if err != nil {
				return nil, fmt.Errorf("ritual failed: %s", status.Status)
			}
			return envelope, nil

		case "running", "pending":
			// Continue polling
			time.Sleep(pollInterval)

		default:
			return nil, fmt.Errorf("unknown run status: %s", status.Status)
		}
	}

	return nil, fmt.Errorf("timeout waiting for ritual to complete")
}
