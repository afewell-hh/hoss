package client

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestStartRitual(t *testing.T) {
	// Mock server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("Expected POST, got %s", r.Method)
		}

		if r.URL.Path != "/api/v1/rituals/hoss-validate/runs" {
			t.Errorf("Expected /api/v1/rituals/hoss-validate/runs, got %s", r.URL.Path)
		}

		resp := RitualStartResponse{
			RunID:  "run-test-123",
			Status: "running",
			Ritual: "hoss-validate",
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}))
	defer server.Close()

	// Create client
	client := NewDemonClient(server.URL, "")

	// Test StartRitual
	input := map[string]interface{}{
		"diagramPath": "samples/topology-min.yaml",
	}

	runID, err := client.StartRitual("hoss-validate", input)
	if err != nil {
		t.Fatalf("StartRitual failed: %v", err)
	}

	if runID != "run-test-123" {
		t.Errorf("Expected runID 'run-test-123', got '%s'", runID)
	}
}

func TestGetRunStatus(t *testing.T) {
	// Mock server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("Expected GET, got %s", r.Method)
		}

		if r.URL.Path != "/api/v1/runs/run-test-123" {
			t.Errorf("Expected /api/v1/runs/run-test-123, got %s", r.URL.Path)
		}

		resp := RunStatus{
			RunID:     "run-test-123",
			Status:    "completed",
			Ritual:    "hoss-validate",
			CreatedAt: "2025-10-05T12:00:00Z",
			UpdatedAt: "2025-10-05T12:01:00Z",
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}))
	defer server.Close()

	// Create client
	client := NewDemonClient(server.URL, "")

	// Test GetRunStatus
	status, err := client.GetRunStatus("run-test-123")
	if err != nil {
		t.Fatalf("GetRunStatus failed: %v", err)
	}

	if status.RunID != "run-test-123" {
		t.Errorf("Expected runID 'run-test-123', got '%s'", status.RunID)
	}

	if status.Status != "completed" {
		t.Errorf("Expected status 'completed', got '%s'", status.Status)
	}
}

func TestGetEnvelope(t *testing.T) {
	// Mock server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("Expected GET, got %s", r.Method)
		}

		if r.URL.Path != "/api/v1/runs/run-test-123/envelope" {
			t.Errorf("Expected /api/v1/runs/run-test-123/envelope, got %s", r.URL.Path)
		}

		envelope := map[string]interface{}{
			"status": "ok",
			"counts": map[string]interface{}{
				"validated": 1,
				"warnings":  0,
				"failures":  0,
			},
			"tool": map[string]interface{}{
				"name":        "hhfab",
				"version":     "v0.41.3",
				"imageDigest": "ghcr.io/afewell-hh/hoss/hhfab@sha256:test",
			},
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(envelope)
	}))
	defer server.Close()

	// Create client
	client := NewDemonClient(server.URL, "")

	// Test GetEnvelope
	envelope, err := client.GetEnvelope("run-test-123")
	if err != nil {
		t.Fatalf("GetEnvelope failed: %v", err)
	}

	status, ok := envelope["status"].(string)
	if !ok || status != "ok" {
		t.Errorf("Expected status 'ok', got '%v'", envelope["status"])
	}

	counts, ok := envelope["counts"].(map[string]interface{})
	if !ok {
		t.Fatalf("Expected counts map, got %T", envelope["counts"])
	}

	validated, ok := counts["validated"].(float64)
	if !ok || validated != 1 {
		t.Errorf("Expected validated=1, got %v", counts["validated"])
	}
}

func TestWaitForRitual_Success(t *testing.T) {
	callCount := 0

	// Mock server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++

		w.Header().Set("Content-Type", "application/json")

		if r.URL.Path == "/api/v1/runs/run-test-123" {
			// First call: running, second call: completed
			status := "running"
			if callCount > 1 {
				status = "completed"
			}

			resp := RunStatus{
				RunID:  "run-test-123",
				Status: status,
				Ritual: "hoss-validate",
			}
			json.NewEncoder(w).Encode(resp)
		} else if r.URL.Path == "/api/v1/runs/run-test-123/envelope" {
			envelope := map[string]interface{}{
				"status": "ok",
			}
			json.NewEncoder(w).Encode(envelope)
		}
	}))
	defer server.Close()

	// Create client
	client := NewDemonClient(server.URL, "")

	// Test WaitForRitual
	envelope, err := client.WaitForRitual("run-test-123", 10*time.Second)
	if err != nil {
		t.Fatalf("WaitForRitual failed: %v", err)
	}

	status, ok := envelope["status"].(string)
	if !ok || status != "ok" {
		t.Errorf("Expected status 'ok', got '%v'", envelope["status"])
	}

	if callCount < 2 {
		t.Errorf("Expected at least 2 status checks, got %d", callCount)
	}
}

func TestWaitForRitual_Timeout(t *testing.T) {
	// Mock server that always returns running
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		resp := RunStatus{
			RunID:  "run-test-123",
			Status: "running",
			Ritual: "hoss-validate",
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer server.Close()

	// Create client
	client := NewDemonClient(server.URL, "")

	// Test WaitForRitual with short timeout
	_, err := client.WaitForRitual("run-test-123", 3*time.Second)
	if err == nil {
		t.Fatal("Expected timeout error, got nil")
	}

	if err.Error() != "timeout waiting for ritual to complete" {
		t.Errorf("Expected timeout error, got: %v", err)
	}
}

func TestAuthentication(t *testing.T) {
	// Mock server that checks for auth header
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if auth != "Bearer test-token" {
			t.Errorf("Expected 'Bearer test-token', got '%s'", auth)
		}

		w.Header().Set("Content-Type", "application/json")
		resp := RitualStartResponse{
			RunID:  "run-test-123",
			Status: "running",
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer server.Close()

	// Create client with token
	client := NewDemonClient(server.URL, "test-token")

	// Test with auth
	input := map[string]interface{}{
		"diagramPath": "test.yaml",
	}

	_, err := client.StartRitual("hoss-validate", input)
	if err != nil {
		t.Fatalf("StartRitual with auth failed: %v", err)
	}
}

func TestStartRitual_NonOKStatus(t *testing.T) {
	// Mock server that returns 400
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte("Invalid request"))
	}))
	defer server.Close()

	client := NewDemonClient(server.URL, "")

	input := map[string]interface{}{
		"diagramPath": "test.yaml",
	}

	_, err := client.StartRitual("hoss-validate", input)
	if err == nil {
		t.Fatal("Expected error for non-OK status, got nil")
	}

	if err.Error() != "API error (status 400): Invalid request" {
		t.Errorf("Unexpected error message: %v", err)
	}
}

func TestStartRitual_InvalidJSON(t *testing.T) {
	// Mock server that returns invalid JSON
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte("invalid json"))
	}))
	defer server.Close()

	client := NewDemonClient(server.URL, "")

	input := map[string]interface{}{
		"diagramPath": "test.yaml",
	}

	_, err := client.StartRitual("hoss-validate", input)
	if err == nil {
		t.Fatal("Expected error for invalid JSON, got nil")
	}
}

func TestGetRunStatus_Error(t *testing.T) {
	// Mock server that returns 500
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte("Internal error"))
	}))
	defer server.Close()

	client := NewDemonClient(server.URL, "")

	_, err := client.GetRunStatus("run-test-123")
	if err == nil {
		t.Fatal("Expected error for 500 status, got nil")
	}
}

func TestGetEnvelope_Error(t *testing.T) {
	// Mock server that returns 404
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte("Not found"))
	}))
	defer server.Close()

	client := NewDemonClient(server.URL, "")

	_, err := client.GetEnvelope("run-nonexistent")
	if err == nil {
		t.Fatal("Expected error for 404 status, got nil")
	}
}
