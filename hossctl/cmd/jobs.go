package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"text/tabwriter"

	"github.com/afewell-hh/hoss/hossctl/pkg/jobstore"
	"github.com/spf13/cobra"
)

var (
	jobsLimit  int
	jobsStatus string
)

var jobsCmd = &cobra.Command{
	Use:   "jobs",
	Short: "List recent validation jobs",
	Long: `List recent validation jobs from local job history.

Jobs are sorted by creation time (newest first). Old jobs are automatically
pruned based on retention policy (last 100 jobs, 7 days max age).

Examples:
  # List all recent jobs
  hossctl jobs

  # List last 10 jobs
  hossctl jobs --limit 10

  # Filter by status
  hossctl jobs --status running

  # Output as JSON
  hossctl jobs --json`,
	Args: cobra.NoArgs,
	RunE: runJobs,
}

func init() {
	rootCmd.AddCommand(jobsCmd)

	jobsCmd.Flags().IntVar(&jobsLimit, "limit", 20, "Maximum number of jobs to show")
	jobsCmd.Flags().StringVar(&jobsStatus, "status", "", "Filter by status (running, completed, failed, cancelled)")
}

func runJobs(cmd *cobra.Command, args []string) error {
	// Initialize job store
	store, err := jobstore.NewJobStore("", 100, 7)
	if err != nil {
		return fmt.Errorf("failed to initialize job store: %w", err)
	}

	// Prune old jobs
	prunedCount, err := store.PruneJobs()
	if err != nil {
		if !outputJSON {
			fmt.Fprintf(os.Stderr, "Warning: failed to prune old jobs: %v\n", err)
		}
	} else if prunedCount > 0 && !outputJSON {
		fmt.Fprintf(os.Stderr, "Pruned %d old job(s)\n", prunedCount)
	}

	// List jobs
	jobs, err := store.ListJobs(jobsLimit, jobsStatus)
	if err != nil {
		return fmt.Errorf("failed to list jobs: %w", err)
	}

	if len(jobs) == 0 {
		if !outputJSON {
			fmt.Println("No jobs found")
		} else {
			fmt.Println("[]")
		}
		return nil
	}

	// Output as JSON
	if outputJSON {
		jobsJSON, err := json.MarshalIndent(jobs, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal jobs: %w", err)
		}
		fmt.Println(string(jobsJSON))
		return nil
	}

	// Output as table
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "JOB ID\tSTATUS\tCREATED AT\tTOPOLOGY")

	for _, job := range jobs {
		// Extract topology file from input
		topology := ""
		if diagramPath, ok := job.Input["diagramPath"].(string); ok {
			topology = diagramPath
		}

		fmt.Fprintf(w, "%s\t%s\t%s\t%s\n",
			job.JobID,
			job.Status,
			job.CreatedAt,
			topology,
		)
	}

	w.Flush()
	return nil
}
