package jobstore

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"sort"
	"time"
)

// JobMetadata represents the metadata for a validation job
type JobMetadata struct {
	JobID       string                 `json:"jobId"`
	RunID       string                 `json:"runId"`
	Status      string                 `json:"status"`
	Ritual      string                 `json:"ritual"`
	Input       map[string]interface{} `json:"input"`
	CreatedAt   string                 `json:"createdAt"`
	UpdatedAt   string                 `json:"updatedAt"`
	CompletedAt *string                `json:"completedAt,omitempty"`
	ExitCode    *int                   `json:"exitCode,omitempty"`
	Error       *string                `json:"error,omitempty"`
}

// JobIndex represents the index of all jobs
type JobIndex struct {
	Jobs       []JobIndexEntry `json:"jobs"`
	LastPruned string          `json:"lastPruned"`
}

// JobIndexEntry represents a single entry in the job index
type JobIndexEntry struct {
	JobID     string `json:"jobId"`
	Status    string `json:"status"`
	CreatedAt string `json:"createdAt"`
}

// JobStore manages persistent job metadata
type JobStore struct {
	baseDir        string
	retentionCount int
	retentionDays  int
}

// NewJobStore creates a new job store
// baseDir defaults to ~/.hossctl/jobs if empty
func NewJobStore(baseDir string, retentionCount, retentionDays int) (*JobStore, error) {
	if baseDir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return nil, fmt.Errorf("failed to get home directory: %w", err)
		}
		baseDir = filepath.Join(home, ".hossctl", "jobs")
	}

	// Create base directory if it doesn't exist
	if err := os.MkdirAll(baseDir, 0700); err != nil {
		return nil, fmt.Errorf("failed to create job store directory: %w", err)
	}

	if retentionCount <= 0 {
		retentionCount = 100
	}
	if retentionDays <= 0 {
		retentionDays = 7
	}

	return &JobStore{
		baseDir:        baseDir,
		retentionCount: retentionCount,
		retentionDays:  retentionDays,
	}, nil
}

// SaveJob saves job metadata to disk
func (s *JobStore) SaveJob(job *JobMetadata) error {
	jobDir := filepath.Join(s.baseDir, job.JobID)

	// Create job directory
	if err := os.MkdirAll(jobDir, 0700); err != nil {
		return fmt.Errorf("failed to create job directory: %w", err)
	}

	// Write metadata
	metadataPath := filepath.Join(jobDir, "metadata.json")
	if err := s.atomicWriteJSON(metadataPath, job, 0600); err != nil {
		return fmt.Errorf("failed to write metadata: %w", err)
	}

	// Update index
	if err := s.updateIndex(job.JobID, job.Status, job.CreatedAt); err != nil {
		return fmt.Errorf("failed to update index: %w", err)
	}

	return nil
}

// GetJob retrieves job metadata from disk
func (s *JobStore) GetJob(jobID string) (*JobMetadata, error) {
	metadataPath := filepath.Join(s.baseDir, jobID, "metadata.json")

	data, err := ioutil.ReadFile(metadataPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("job not found: %s", jobID)
		}
		return nil, fmt.Errorf("failed to read metadata: %w", err)
	}

	var job JobMetadata
	if err := json.Unmarshal(data, &job); err != nil {
		return nil, fmt.Errorf("failed to parse metadata: %w", err)
	}

	return &job, nil
}

// SaveEnvelope saves the result envelope for a job
func (s *JobStore) SaveEnvelope(jobID string, envelope map[string]interface{}) error {
	jobDir := filepath.Join(s.baseDir, jobID)

	// Ensure job directory exists
	if _, err := os.Stat(jobDir); os.IsNotExist(err) {
		return fmt.Errorf("job not found: %s", jobID)
	}

	// Write envelope
	envelopePath := filepath.Join(jobDir, "envelope.json")
	if err := s.atomicWriteJSON(envelopePath, envelope, 0600); err != nil {
		return fmt.Errorf("failed to write envelope: %w", err)
	}

	return nil
}

// GetEnvelope retrieves the cached envelope for a job
func (s *JobStore) GetEnvelope(jobID string) (map[string]interface{}, error) {
	envelopePath := filepath.Join(s.baseDir, jobID, "envelope.json")

	data, err := ioutil.ReadFile(envelopePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("envelope not found for job: %s", jobID)
		}
		return nil, fmt.Errorf("failed to read envelope: %w", err)
	}

	var envelope map[string]interface{}
	if err := json.Unmarshal(data, &envelope); err != nil {
		return nil, fmt.Errorf("failed to parse envelope: %w", err)
	}

	return envelope, nil
}

// ListJobs returns a list of all jobs sorted by creation time (newest first)
func (s *JobStore) ListJobs(limit int, statusFilter string) ([]*JobMetadata, error) {
	index, err := s.loadIndex()
	if err != nil {
		// If index doesn't exist yet, return empty list
		if os.IsNotExist(err) {
			return []*JobMetadata{}, nil
		}
		return nil, fmt.Errorf("failed to load index: %w", err)
	}

	// Filter by status if specified
	var filtered []JobIndexEntry
	for _, entry := range index.Jobs {
		if statusFilter == "" || entry.Status == statusFilter {
			filtered = append(filtered, entry)
		}
	}

	// Apply limit
	if limit > 0 && len(filtered) > limit {
		filtered = filtered[:limit]
	}

	// Load full metadata for each job
	jobs := make([]*JobMetadata, 0, len(filtered))
	for _, entry := range filtered {
		job, err := s.GetJob(entry.JobID)
		if err != nil {
			// Skip jobs that can't be loaded (may have been deleted)
			continue
		}
		jobs = append(jobs, job)
	}

	return jobs, nil
}

// PruneJobs removes old jobs based on retention policy
func (s *JobStore) PruneJobs() (int, error) {
	index, err := s.loadIndex()
	if err != nil {
		if os.IsNotExist(err) {
			return 0, nil
		}
		return 0, fmt.Errorf("failed to load index: %w", err)
	}

	now := time.Now()
	cutoffTime := now.AddDate(0, 0, -s.retentionDays)
	prunedCount := 0

	// Find jobs to prune
	var toKeep []JobIndexEntry
	for _, entry := range index.Jobs {
		// Parse creation time
		createdAt, err := time.Parse(time.RFC3339, entry.CreatedAt)
		if err != nil {
			// Keep if we can't parse the time
			toKeep = append(toKeep, entry)
			continue
		}

		// Check if job is too old
		if createdAt.Before(cutoffTime) {
			// Delete job directory
			jobDir := filepath.Join(s.baseDir, entry.JobID)
			if err := os.RemoveAll(jobDir); err != nil {
				// Log error but continue
				fmt.Fprintf(os.Stderr, "Warning: failed to delete job %s: %v\n", entry.JobID, err)
			} else {
				prunedCount++
			}
		} else {
			toKeep = append(toKeep, entry)
		}
	}

	// Apply count-based retention (keep only most recent N jobs)
	if len(toKeep) > s.retentionCount {
		// Jobs are already sorted newest first, so prune oldest
		for _, entry := range toKeep[s.retentionCount:] {
			jobDir := filepath.Join(s.baseDir, entry.JobID)
			if err := os.RemoveAll(jobDir); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to delete job %s: %v\n", entry.JobID, err)
			} else {
				prunedCount++
			}
		}
		toKeep = toKeep[:s.retentionCount]
	}

	// Update index
	index.Jobs = toKeep
	index.LastPruned = now.Format(time.RFC3339)
	if err := s.saveIndex(index); err != nil {
		return prunedCount, fmt.Errorf("failed to save index: %w", err)
	}

	return prunedCount, nil
}

// atomicWriteJSON writes JSON data to a file atomically
func (s *JobStore) atomicWriteJSON(path string, data interface{}, perm os.FileMode) error {
	// Marshal JSON
	jsonData, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal JSON: %w", err)
	}

	// Write to temp file
	tmpPath := path + ".tmp"
	if err := ioutil.WriteFile(tmpPath, jsonData, perm); err != nil {
		return fmt.Errorf("failed to write temp file: %w", err)
	}

	// Atomic rename
	if err := os.Rename(tmpPath, path); err != nil {
		os.Remove(tmpPath) // Clean up temp file
		return fmt.Errorf("failed to rename file: %w", err)
	}

	return nil
}

// updateIndex updates the job index with new/updated job entry
func (s *JobStore) updateIndex(jobID, status, createdAt string) error {
	index, err := s.loadIndex()
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to load index: %w", err)
	}
	if index == nil {
		index = &JobIndex{
			Jobs:       []JobIndexEntry{},
			LastPruned: time.Now().Format(time.RFC3339),
		}
	}

	// Check if job already exists in index
	found := false
	for i, entry := range index.Jobs {
		if entry.JobID == jobID {
			// Update existing entry
			index.Jobs[i].Status = status
			found = true
			break
		}
	}

	// Add new entry if not found
	if !found {
		index.Jobs = append(index.Jobs, JobIndexEntry{
			JobID:     jobID,
			Status:    status,
			CreatedAt: createdAt,
		})
	}

	// Sort by creation time (newest first)
	sort.Slice(index.Jobs, func(i, j int) bool {
		// Parse times for comparison
		ti, _ := time.Parse(time.RFC3339, index.Jobs[i].CreatedAt)
		tj, _ := time.Parse(time.RFC3339, index.Jobs[j].CreatedAt)
		return ti.After(tj)
	})

	return s.saveIndex(index)
}

// loadIndex loads the job index from disk
func (s *JobStore) loadIndex() (*JobIndex, error) {
	indexPath := filepath.Join(s.baseDir, "index.json")

	data, err := ioutil.ReadFile(indexPath)
	if err != nil {
		return nil, err
	}

	var index JobIndex
	if err := json.Unmarshal(data, &index); err != nil {
		return nil, fmt.Errorf("failed to parse index: %w", err)
	}

	return &index, nil
}

// saveIndex saves the job index to disk
func (s *JobStore) saveIndex(index *JobIndex) error {
	indexPath := filepath.Join(s.baseDir, "index.json")
	return s.atomicWriteJSON(indexPath, index, 0600)
}
