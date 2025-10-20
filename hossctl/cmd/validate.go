package cmd

import (
	"encoding/json"
	"fmt"
	"math"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/afewell-hh/hoss/hossctl/pkg/client"
	"github.com/afewell-hh/hoss/hossctl/pkg/jobstore"
	"github.com/spf13/cobra"
)

var (
	strictMode       bool
	fabConfigPath    string
	waitForResults   bool
	useStreaming     bool
	timeout          time.Duration
	retries          int
	backoffStrategy  string
	backoffBase      time.Duration
	backoffMultiplier float64
	backoffMax       time.Duration
)

var validateCmd = &cobra.Command{
	Use:   "validate <diagram.yaml>",
	Short: "Validate a Hedgehog fabric wiring diagram",
	Long: `Validate a Hedgehog fabric wiring diagram using the hoss-validate ritual.

The diagram file is sent to the Demon platform, which executes the validation
using the digest-pinned hhfab container. Results are returned as a JSON envelope.

Examples:
  # Validate a diagram
  hossctl validate samples/topology-min.yaml

  # Validate with strict mode (zero warnings allowed)
  hossctl validate --strict samples/topology-min.yaml

  # Validate and wait for results
  hossctl validate --wait samples/topology-min.yaml

  # Launch validation asynchronously (no-wait mode)
  hossctl validate --no-wait samples/topology-large.yaml

  # Output JSON only
  hossctl validate --json samples/topology-min.yaml`,
	Args: cobra.ExactArgs(1),
	RunE: runValidate,
}

func init() {
	rootCmd.AddCommand(validateCmd)

	validateCmd.Flags().BoolVar(&strictMode, "strict", false, "Enable strict validation (zero warnings allowed)")
	validateCmd.Flags().StringVar(&fabConfigPath, "fab-config", "", "Path to fab.yaml configuration file")
	validateCmd.Flags().BoolVar(&waitForResults, "wait", true, "Wait for validation to complete (use --no-wait for async)")
	validateCmd.Flags().BoolVar(&useStreaming, "stream", false, "Use SSE streaming for real-time progress updates")
	validateCmd.Flags().DurationVar(&timeout, "timeout", 5*time.Minute, "Timeout for validation")

	// Retry and backoff flags
	validateCmd.Flags().IntVar(&retries, "retries", 0, "Maximum number of retry attempts (default: 0, no retries)")
	validateCmd.Flags().StringVar(&backoffStrategy, "backoff", "exponential", "Backoff strategy: exponential, linear, or constant")
	validateCmd.Flags().DurationVar(&backoffBase, "backoff-base", 2*time.Second, "Base delay for backoff")
	validateCmd.Flags().Float64Var(&backoffMultiplier, "backoff-multiplier", 2.0, "Multiplier for exponential backoff")
	validateCmd.Flags().DurationVar(&backoffMax, "backoff-max", 60*time.Second, "Maximum delay cap for backoff")
}

// calculateBackoff computes the delay for the given attempt number based on backoff strategy
func calculateBackoff(attempt int) time.Duration {
	var delay time.Duration

	switch backoffStrategy {
	case "exponential":
		// delay = min(base * multiplier^attempt, max)
		delay = time.Duration(float64(backoffBase) * math.Pow(backoffMultiplier, float64(attempt)))
	case "linear":
		// delay = min(base * attempt, max)
		delay = backoffBase * time.Duration(attempt+1)
	case "constant":
		// delay = base (always same)
		delay = backoffBase
	default:
		// Default to exponential
		delay = time.Duration(float64(backoffBase) * math.Pow(backoffMultiplier, float64(attempt)))
	}

	// Cap at maximum
	if delay > backoffMax {
		delay = backoffMax
	}

	return delay
}

// isRetriableError checks if an error is retriable (transient network issues, 5xx errors)
func isRetriableError(err error) bool {
	if err == nil {
		return false
	}

	errMsg := err.Error()

	// Network errors (connection refused, timeout, etc.)
	if strings.Contains(errMsg, "connection refused") ||
		strings.Contains(errMsg, "timeout") ||
		strings.Contains(errMsg, "no such host") ||
		strings.Contains(errMsg, "network is unreachable") ||
		strings.Contains(errMsg, "connection reset") {
		return true
	}

	// Check for network error types
	if _, ok := err.(net.Error); ok {
		return true
	}

	// HTTP 5xx errors (server errors)
	if strings.Contains(errMsg, "status 5") ||
		strings.Contains(errMsg, "502") ||
		strings.Contains(errMsg, "503") ||
		strings.Contains(errMsg, "504") {
		return true
	}

	// Container startup failures
	if strings.Contains(errMsg, "container startup") ||
		strings.Contains(errMsg, "failed to start container") {
		return true
	}

	// Stream connection errors
	if strings.Contains(errMsg, "failed to connect to stream") ||
		strings.Contains(errMsg, "stream error") {
		return true
	}

	return false
}

func runValidate(cmd *cobra.Command, args []string) error {
	diagramPath := args[0]

	// Validate file exists
	absPath, err := filepath.Abs(diagramPath)
	if err != nil {
		return fmt.Errorf("invalid diagram path: %w", err)
	}

	if _, err := os.Stat(absPath); os.IsNotExist(err) {
		return fmt.Errorf("diagram file not found: %s", absPath)
	}

	// Build validation request
	request := map[string]interface{}{
		"diagramPath": absPath,
		"strict":      strictMode,
	}

	if fabConfigPath != "" {
		absFabPath, err := filepath.Abs(fabConfigPath)
		if err != nil {
			return fmt.Errorf("invalid fab config path: %w", err)
		}
		request["fabConfigPath"] = absFabPath
	}

	// Retry loop
	var envelope map[string]interface{}
	maxAttempts := retries + 1 // retries=0 means 1 attempt total

	for attempt := 0; attempt < maxAttempts; attempt++ {
		if attempt > 0 {
			// Calculate backoff delay
			delay := calculateBackoff(attempt - 1)

			// Log retry attempt
			if !outputJSON {
				fmt.Fprintf(os.Stderr, "Retry %d/%d in %s...\n", attempt, retries, delay)
			} else {
				retryEvent := map[string]interface{}{
					"event":          "retry",
					"attempt":        attempt,
					"maxRetries":     retries,
					"backoffSeconds": delay.Seconds(),
					"timestamp":      time.Now().UTC().Format(time.RFC3339Nano),
				}
				eventJSON, _ := json.Marshal(retryEvent)
				fmt.Println(string(eventJSON))
			}

			// Wait before retrying
			time.Sleep(delay)
		}

		// Create Demon client (fresh for each attempt)
		demonClient := client.NewDemonClient(getDemonURL(), getDemonToken())

		// Start validation ritual
		if !outputJSON && attempt == 0 {
			fmt.Fprintf(os.Stderr, "Starting validation for: %s\n", diagramPath)
			if strictMode {
				fmt.Fprintf(os.Stderr, "Strict mode: enabled\n")
			}
		}

		runID, err := demonClient.StartRitual("hoss-validate", request)
		if err != nil {
			// Check if error is retriable
			if isRetriableError(err) && attempt < maxAttempts-1 {
				if !outputJSON {
					fmt.Fprintf(os.Stderr, "Error: %v (retriable)\n", err)
				} else {
					errorEvent := map[string]interface{}{
						"event":      "error",
						"error":      err.Error(),
						"retriable":  true,
						"timestamp":  time.Now().UTC().Format(time.RFC3339Nano),
					}
					eventJSON, _ := json.Marshal(errorEvent)
					fmt.Println(string(eventJSON))
				}
				continue // Retry
			}
			return fmt.Errorf("failed to start validation ritual: %w", err)
		}

		if !outputJSON {
			fmt.Fprintf(os.Stderr, "Ritual started: %s\n", runID)
		}

		// If --no-wait, save job metadata and return job ID
		if !waitForResults {
			// Initialize job store
			store, err := jobstore.NewJobStore("", 100, 7)
			if err != nil {
				return fmt.Errorf("failed to initialize job store: %w", err)
			}

			// Save job metadata
			job := &jobstore.JobMetadata{
				JobID:     runID,
				RunID:     runID,
				Status:    "pending",
				Ritual:    "hoss-validate",
				Input:     request,
				CreatedAt: time.Now().Format(time.RFC3339),
				UpdatedAt: time.Now().Format(time.RFC3339),
			}

			if err := store.SaveJob(job); err != nil {
				// Log warning but don't fail
				if !outputJSON {
					fmt.Fprintf(os.Stderr, "Warning: failed to save job metadata: %v\n", err)
				}
			}

			// Return job ID (just the ID, not JSON object)
			fmt.Println(runID)
			return nil
		}

		// Wait for completion (with or without streaming)
		if useStreaming {
			// Use SSE streaming for real-time updates
			if !outputJSON {
				fmt.Fprintf(os.Stderr, "Streaming validation progress...\n")
			}

			envelope, err = demonClient.StreamRitual(runID, timeout, func(event client.SSEEvent) error {
				// Emit JSON events if in JSON mode
				if outputJSON {
					eventJSON, err := json.Marshal(map[string]interface{}{
						"event":     event.Type,
						"timestamp": time.Now().UTC().Format(time.RFC3339Nano),
						"data":      event.Data,
					})
					if err != nil {
						return err
					}
					fmt.Println(string(eventJSON))
				} else {
					// Human-readable progress updates
					switch event.Type {
					case "status":
						if status, ok := event.Data["status"].(string); ok {
							fmt.Fprintf(os.Stderr, "Status: %s\n", status)
						}
					case "envelope":
						fmt.Fprintf(os.Stderr, "Received results\n")
					case "heartbeat":
						// Silently ignore heartbeats in human mode
					}
				}
				return nil
			})

			if err != nil {
				// Check if error is retriable
				if isRetriableError(err) && attempt < maxAttempts-1 {
					if !outputJSON {
						fmt.Fprintf(os.Stderr, "Error: %v (retriable)\n", err)
					} else {
						errorEvent := map[string]interface{}{
							"event":     "error",
							"error":     err.Error(),
							"retriable": true,
							"timestamp": time.Now().UTC().Format(time.RFC3339Nano),
						}
						eventJSON, _ := json.Marshal(errorEvent)
						fmt.Println(string(eventJSON))
					}
					continue // Retry
				}
				return fmt.Errorf("streaming validation failed: %w", err)
			}
		} else {
			// Use polling (legacy mode)
			if !outputJSON {
				fmt.Fprintf(os.Stderr, "Waiting for results...\n")
			}

			envelope, err = demonClient.WaitForRitual(runID, timeout)
			if err != nil {
				// Check if error is retriable
				if isRetriableError(err) && attempt < maxAttempts-1 {
					if !outputJSON {
						fmt.Fprintf(os.Stderr, "Error: %v (retriable)\n", err)
					} else {
						errorEvent := map[string]interface{}{
							"event":     "error",
							"error":     err.Error(),
							"retriable": true,
							"timestamp": time.Now().UTC().Format(time.RFC3339Nano),
						}
						eventJSON, _ := json.Marshal(errorEvent)
						fmt.Println(string(eventJSON))
					}
					continue // Retry
				}
				return fmt.Errorf("validation failed: %w", err)
			}
		}

		// Success - break out of retry loop
		break
	}

	// Output final envelope (unless already emitted via streaming)
	if !useStreaming || !outputJSON {
		envelopeJSON, err := json.MarshalIndent(envelope, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal envelope: %w", err)
		}
		fmt.Println(string(envelopeJSON))
	}

	// Check validation status
	status, ok := envelope["status"].(string)
	if !ok || status == "" {
		return fmt.Errorf("invalid envelope: missing status")
	}

	if status == "error" {
		return fmt.Errorf("validation failed")
	}

	if status == "warning" && strictMode {
		return fmt.Errorf("validation warnings not allowed in strict mode")
	}

	return nil
}
