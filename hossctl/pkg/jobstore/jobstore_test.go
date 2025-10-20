package jobstore

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestNewJobStore(t *testing.T) {
	// Create temp directory
	tmpDir := filepath.Join(os.TempDir(), "hossctl-test-jobstore")
	defer os.RemoveAll(tmpDir)

	store, err := NewJobStore(tmpDir, 100, 7)
	if err != nil {
		t.Fatalf("Failed to create job store: %v", err)
	}

	if store.baseDir != tmpDir {
		t.Errorf("Expected baseDir %s, got %s", tmpDir, store.baseDir)
	}

	// Check that directory was created
	if _, err := os.Stat(tmpDir); os.IsNotExist(err) {
		t.Errorf("Base directory was not created")
	}
}

func TestSaveAndGetJob(t *testing.T) {
	tmpDir := filepath.Join(os.TempDir(), "hossctl-test-save-get")
	defer os.RemoveAll(tmpDir)

	store, err := NewJobStore(tmpDir, 100, 7)
	if err != nil {
		t.Fatalf("Failed to create job store: %v", err)
	}

	// Create test job
	job := &JobMetadata{
		JobID:     "test-job-123",
		RunID:     "test-job-123",
		Status:    "running",
		Ritual:    "hoss-validate",
		Input:     map[string]interface{}{"diagramPath": "/path/to/topology.yaml"},
		CreatedAt: time.Now().Format(time.RFC3339),
		UpdatedAt: time.Now().Format(time.RFC3339),
	}

	// Save job
	if err := store.SaveJob(job); err != nil {
		t.Fatalf("Failed to save job: %v", err)
	}

	// Retrieve job
	retrieved, err := store.GetJob("test-job-123")
	if err != nil {
		t.Fatalf("Failed to get job: %v", err)
	}

	// Verify fields
	if retrieved.JobID != job.JobID {
		t.Errorf("JobID mismatch: expected %s, got %s", job.JobID, retrieved.JobID)
	}
	if retrieved.Status != job.Status {
		t.Errorf("Status mismatch: expected %s, got %s", job.Status, retrieved.Status)
	}
	if retrieved.Ritual != job.Ritual {
		t.Errorf("Ritual mismatch: expected %s, got %s", job.Ritual, retrieved.Ritual)
	}
}

func TestGetJobNotFound(t *testing.T) {
	tmpDir := filepath.Join(os.TempDir(), "hossctl-test-notfound")
	defer os.RemoveAll(tmpDir)

	store, err := NewJobStore(tmpDir, 100, 7)
	if err != nil {
		t.Fatalf("Failed to create job store: %v", err)
	}

	// Try to get non-existent job
	_, err = store.GetJob("non-existent-job")
	if err == nil {
		t.Errorf("Expected error for non-existent job, got nil")
	}
}

func TestSaveAndGetEnvelope(t *testing.T) {
	tmpDir := filepath.Join(os.TempDir(), "hossctl-test-envelope")
	defer os.RemoveAll(tmpDir)

	store, err := NewJobStore(tmpDir, 100, 7)
	if err != nil {
		t.Fatalf("Failed to create job store: %v", err)
	}

	// Create job first
	job := &JobMetadata{
		JobID:     "test-job-456",
		RunID:     "test-job-456",
		Status:    "completed",
		Ritual:    "hoss-validate",
		Input:     map[string]interface{}{"diagramPath": "/path/to/topology.yaml"},
		CreatedAt: time.Now().Format(time.RFC3339),
		UpdatedAt: time.Now().Format(time.RFC3339),
	}
	if err := store.SaveJob(job); err != nil {
		t.Fatalf("Failed to save job: %v", err)
	}

	// Save envelope
	envelope := map[string]interface{}{
		"status":    "ok",
		"validated": 1,
		"tool": map[string]interface{}{
			"name":    "hhfab",
			"version": "1.0.0",
		},
	}
	if err := store.SaveEnvelope("test-job-456", envelope); err != nil {
		t.Fatalf("Failed to save envelope: %v", err)
	}

	// Retrieve envelope
	retrieved, err := store.GetEnvelope("test-job-456")
	if err != nil {
		t.Fatalf("Failed to get envelope: %v", err)
	}

	// Verify envelope
	if status, ok := retrieved["status"].(string); !ok || status != "ok" {
		t.Errorf("Expected status 'ok', got %v", retrieved["status"])
	}
}

func TestListJobs(t *testing.T) {
	tmpDir := filepath.Join(os.TempDir(), "hossctl-test-list")
	defer os.RemoveAll(tmpDir)

	store, err := NewJobStore(tmpDir, 100, 7)
	if err != nil {
		t.Fatalf("Failed to create job store: %v", err)
	}

	// Create multiple jobs
	now := time.Now()
	jobs := []*JobMetadata{
		{
			JobID:     "job-1",
			RunID:     "job-1",
			Status:    "completed",
			Ritual:    "hoss-validate",
			Input:     map[string]interface{}{},
			CreatedAt: now.Add(-2 * time.Hour).Format(time.RFC3339),
			UpdatedAt: now.Add(-2 * time.Hour).Format(time.RFC3339),
		},
		{
			JobID:     "job-2",
			RunID:     "job-2",
			Status:    "running",
			Ritual:    "hoss-validate",
			Input:     map[string]interface{}{},
			CreatedAt: now.Add(-1 * time.Hour).Format(time.RFC3339),
			UpdatedAt: now.Add(-1 * time.Hour).Format(time.RFC3339),
		},
		{
			JobID:     "job-3",
			RunID:     "job-3",
			Status:    "failed",
			Ritual:    "hoss-validate",
			Input:     map[string]interface{}{},
			CreatedAt: now.Format(time.RFC3339),
			UpdatedAt: now.Format(time.RFC3339),
		},
	}

	for _, job := range jobs {
		if err := store.SaveJob(job); err != nil {
			t.Fatalf("Failed to save job %s: %v", job.JobID, err)
		}
	}

	// List all jobs
	allJobs, err := store.ListJobs(0, "")
	if err != nil {
		t.Fatalf("Failed to list jobs: %v", err)
	}
	if len(allJobs) != 3 {
		t.Errorf("Expected 3 jobs, got %d", len(allJobs))
	}

	// Check sorting (newest first)
	if allJobs[0].JobID != "job-3" {
		t.Errorf("Expected newest job first (job-3), got %s", allJobs[0].JobID)
	}

	// List with limit
	limitedJobs, err := store.ListJobs(2, "")
	if err != nil {
		t.Fatalf("Failed to list jobs with limit: %v", err)
	}
	if len(limitedJobs) != 2 {
		t.Errorf("Expected 2 jobs with limit, got %d", len(limitedJobs))
	}

	// Filter by status
	runningJobs, err := store.ListJobs(0, "running")
	if err != nil {
		t.Fatalf("Failed to list running jobs: %v", err)
	}
	if len(runningJobs) != 1 {
		t.Errorf("Expected 1 running job, got %d", len(runningJobs))
	}
	if runningJobs[0].JobID != "job-2" {
		t.Errorf("Expected job-2, got %s", runningJobs[0].JobID)
	}
}

func TestPruneJobs(t *testing.T) {
	tmpDir := filepath.Join(os.TempDir(), "hossctl-test-prune")
	defer os.RemoveAll(tmpDir)

	store, err := NewJobStore(tmpDir, 2, 1) // Keep 2 jobs, 1 day retention
	if err != nil {
		t.Fatalf("Failed to create job store: %v", err)
	}

	// Create jobs with different ages
	now := time.Now()
	jobs := []*JobMetadata{
		{
			JobID:     "old-job",
			RunID:     "old-job",
			Status:    "completed",
			Ritual:    "hoss-validate",
			Input:     map[string]interface{}{},
			CreatedAt: now.AddDate(0, 0, -2).Format(time.RFC3339), // 2 days old
			UpdatedAt: now.AddDate(0, 0, -2).Format(time.RFC3339),
		},
		{
			JobID:     "recent-job-1",
			RunID:     "recent-job-1",
			Status:    "completed",
			Ritual:    "hoss-validate",
			Input:     map[string]interface{}{},
			CreatedAt: now.Add(-2 * time.Hour).Format(time.RFC3339), // 2 hours old
			UpdatedAt: now.Add(-2 * time.Hour).Format(time.RFC3339),
		},
		{
			JobID:     "recent-job-2",
			RunID:     "recent-job-2",
			Status:    "completed",
			Ritual:    "hoss-validate",
			Input:     map[string]interface{}{},
			CreatedAt: now.Add(-1 * time.Hour).Format(time.RFC3339), // 1 hour old
			UpdatedAt: now.Add(-1 * time.Hour).Format(time.RFC3339),
		},
		{
			JobID:     "recent-job-3",
			RunID:     "recent-job-3",
			Status:    "completed",
			Ritual:    "hoss-validate",
			Input:     map[string]interface{}{},
			CreatedAt: now.Format(time.RFC3339), // Just created
			UpdatedAt: now.Format(time.RFC3339),
		},
	}

	for _, job := range jobs {
		if err := store.SaveJob(job); err != nil {
			t.Fatalf("Failed to save job %s: %v", job.JobID, err)
		}
	}

	// Prune jobs
	prunedCount, err := store.PruneJobs()
	if err != nil {
		t.Fatalf("Failed to prune jobs: %v", err)
	}

	// Should prune: old-job (too old) + recent-job-1 (exceeds retention count)
	// Keep: recent-job-2, recent-job-3 (newest 2)
	if prunedCount < 1 {
		t.Errorf("Expected at least 1 job pruned (old job), got %d", prunedCount)
	}

	// List remaining jobs
	remainingJobs, err := store.ListJobs(0, "")
	if err != nil {
		t.Fatalf("Failed to list remaining jobs: %v", err)
	}

	// Should have at most 2 jobs (retention count)
	if len(remainingJobs) > 2 {
		t.Errorf("Expected at most 2 jobs after pruning, got %d", len(remainingJobs))
	}

	// Old job should be gone
	_, err = store.GetJob("old-job")
	if err == nil {
		t.Errorf("Old job should have been pruned")
	}
}
