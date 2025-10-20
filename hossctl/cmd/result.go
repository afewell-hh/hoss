package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/afewell-hh/hoss/hossctl/pkg/client"
	"github.com/afewell-hh/hoss/hossctl/pkg/jobstore"
	"github.com/spf13/cobra"
)

var (
	refreshResult bool
	outputFile    string
)

var resultCmd = &cobra.Command{
	Use:   "result <job-id>",
	Short: "Retrieve the result envelope for a completed job",
	Long: `Retrieve the result envelope for a completed validation job.

Results are cached locally after first retrieval. Use --refresh to force
re-fetch from the Demon platform.

Examples:
  # Get result for a job
  hossctl result abc123-def456-789

  # Force refresh from Demon API
  hossctl result abc123-def456-789 --refresh

  # Save to file
  hossctl result abc123-def456-789 --output result.json`,
	Args: cobra.ExactArgs(1),
	RunE: runResult,
}

func init() {
	rootCmd.AddCommand(resultCmd)

	resultCmd.Flags().BoolVar(&refreshResult, "refresh", false, "Force re-fetch from Demon API (ignore cache)")
	resultCmd.Flags().StringVarP(&outputFile, "output", "o", "", "Write result to file instead of stdout")
}

func runResult(cmd *cobra.Command, args []string) error {
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

	// Check if job is completed
	if job.Status != "completed" && job.Status != "success" && job.Status != "failed" && job.Status != "error" {
		return fmt.Errorf("job is still running (status: %s)", job.Status)
	}

	var envelope map[string]interface{}

	// Try to get cached envelope first (unless refresh is requested)
	if !refreshResult {
		cachedEnvelope, err := store.GetEnvelope(jobID)
		if err == nil {
			envelope = cachedEnvelope
			if !outputJSON && outputFile == "" {
				fmt.Fprintf(os.Stderr, "Using cached result\n")
			}
		}
	}

	// Fetch from Demon API if not cached or refresh requested
	if envelope == nil {
		demonClient := client.NewDemonClient(getDemonURL(), getDemonToken())

		fetchedEnvelope, err := demonClient.GetEnvelope(job.RunID)
		if err != nil {
			// If Demon API is unavailable, try cache as fallback
			cachedEnvelope, cacheErr := store.GetEnvelope(jobID)
			if cacheErr != nil {
				return fmt.Errorf("failed to fetch envelope from Demon API and no cache available: %w", err)
			}

			envelope = cachedEnvelope
			if !outputJSON && outputFile == "" {
				fmt.Fprintf(os.Stderr, "Warning: Demon API unavailable, using cached result\n")
			}
		} else {
			envelope = fetchedEnvelope

			// Cache the envelope
			if err := store.SaveEnvelope(jobID, envelope); err != nil {
				if !outputJSON && outputFile == "" {
					fmt.Fprintf(os.Stderr, "Warning: failed to cache envelope: %v\n", err)
				}
			}
		}
	}

	// Marshal envelope
	envelopeJSON, err := json.MarshalIndent(envelope, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal envelope: %w", err)
	}

	// Output envelope
	if outputFile != "" {
		// Write to file
		if err := os.WriteFile(outputFile, envelopeJSON, 0644); err != nil {
			return fmt.Errorf("failed to write to file: %w", err)
		}
		if !outputJSON {
			fmt.Fprintf(os.Stderr, "Result written to %s\n", outputFile)
		}
	} else {
		// Write to stdout
		fmt.Println(string(envelopeJSON))
	}

	// Exit with appropriate code based on validation status
	if status, ok := envelope["status"].(string); ok {
		if status == "error" {
			os.Exit(1)
		}
	}

	return nil
}
