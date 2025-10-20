package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/afewell-hh/hoss/hossctl/pkg/client"
	"github.com/afewell-hh/hoss/hossctl/pkg/jobstore"
	"github.com/spf13/cobra"
)

var (
	waitForCompletion bool
	statusTimeout     time.Duration
	statusInterval    time.Duration
)

var statusCmd = &cobra.Command{
	Use:   "status <job-id>",
	Short: "Check the status of a validation job",
	Long: `Check the status of a validation job.

Polls the Demon platform for the current job status and updates local metadata.

Examples:
  # Check job status
  hossctl status abc123-def456-789

  # Wait for job to complete
  hossctl status abc123-def456-789 --wait --timeout 10m

  # Poll with custom interval
  hossctl status abc123-def456-789 --wait --interval 10s`,
	Args: cobra.ExactArgs(1),
	RunE: runStatus,
}

func init() {
	rootCmd.AddCommand(statusCmd)

	statusCmd.Flags().BoolVar(&waitForCompletion, "wait", false, "Wait for job to complete")
	statusCmd.Flags().DurationVar(&statusTimeout, "timeout", 5*time.Minute, "Timeout for wait")
	statusCmd.Flags().DurationVar(&statusInterval, "interval", 5*time.Second, "Polling interval")
}

func runStatus(cmd *cobra.Command, args []string) error {
	jobID := args[0]

	// Initialize job store
	store, err := jobstore.NewJobStore("", 100, 7)
	if err != nil {
		return fmt.Errorf("failed to initialize job store: %w", err)
	}

	// Get job metadata
	job, err := store.GetJob(jobID)
	if err != nil {
		return fmt.Errorf("job not found: %s", jobID)
	}

	// Create Demon client
	demonClient := client.NewDemonClient(getDemonURL(), getDemonToken())

	// Poll for status
	deadline := time.Now().Add(statusTimeout)
	for {
		// Get current status from Demon API
		status, err := demonClient.GetRunStatus(job.RunID)
		if err != nil {
			// If Demon API is unavailable, return cached status
			if !outputJSON {
				fmt.Fprintf(os.Stderr, "Warning: Demon API unavailable, using cached data\n")
			}
			statusJSON, _ := json.MarshalIndent(job, "", "  ")
			fmt.Println(string(statusJSON))
			return nil
		}

		// Update job metadata
		job.Status = status.Status
		job.UpdatedAt = status.UpdatedAt
		if status.Status == "completed" || status.Status == "success" || status.Status == "failed" || status.Status == "error" {
			completedAt := time.Now().Format(time.RFC3339)
			job.CompletedAt = &completedAt
		}

		// Save updated metadata
		if err := store.SaveJob(job); err != nil {
			if !outputJSON {
				fmt.Fprintf(os.Stderr, "Warning: failed to update job metadata: %v\n", err)
			}
		}

		// Output status
		statusOutput := map[string]interface{}{
			"jobId":     job.JobID,
			"status":    job.Status,
			"ritual":    job.Ritual,
			"createdAt": job.CreatedAt,
			"updatedAt": job.UpdatedAt,
		}
		if job.CompletedAt != nil {
			statusOutput["completedAt"] = *job.CompletedAt
		}

		statusJSON, _ := json.MarshalIndent(statusOutput, "", "  ")
		fmt.Println(string(statusJSON))

		// Check completion status
		switch job.Status {
		case "completed", "success":
			return nil // Exit code 0
		case "failed", "error":
			os.Exit(1) // Exit code 1
			return nil
		case "cancelled":
			os.Exit(1) // Exit code 1
			return nil
		}

		// If not waiting, exit with code 3 (still running)
		if !waitForCompletion {
			os.Exit(3)
			return nil
		}

		// Check timeout
		if time.Now().After(deadline) {
			return fmt.Errorf("timeout waiting for job to complete")
		}

		// Wait before next poll
		time.Sleep(statusInterval)
	}
}
