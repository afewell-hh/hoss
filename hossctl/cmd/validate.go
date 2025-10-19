package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/afewell-hh/hoss/hossctl/pkg/client"
	"github.com/spf13/cobra"
)

var (
	strictMode     bool
	fabConfigPath  string
	waitForResults bool
	useStreaming   bool
	timeout        time.Duration
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

  # Output JSON only
  hossctl validate --json samples/topology-min.yaml`,
	Args: cobra.ExactArgs(1),
	RunE: runValidate,
}

func init() {
	rootCmd.AddCommand(validateCmd)

	validateCmd.Flags().BoolVar(&strictMode, "strict", false, "Enable strict validation (zero warnings allowed)")
	validateCmd.Flags().StringVar(&fabConfigPath, "fab-config", "", "Path to fab.yaml configuration file")
	validateCmd.Flags().BoolVar(&waitForResults, "wait", true, "Wait for validation to complete")
	validateCmd.Flags().BoolVar(&useStreaming, "stream", false, "Use SSE streaming for real-time progress updates")
	validateCmd.Flags().DurationVar(&timeout, "timeout", 5*time.Minute, "Timeout for validation")
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

	// Create Demon client
	demonClient := client.NewDemonClient(getDemonURL(), getDemonToken())

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

	// Start validation ritual
	if !outputJSON {
		fmt.Fprintf(os.Stderr, "Starting validation for: %s\n", diagramPath)
		if strictMode {
			fmt.Fprintf(os.Stderr, "Strict mode: enabled\n")
		}
	}

	runID, err := demonClient.StartRitual("hoss-validate", request)
	if err != nil {
		return fmt.Errorf("failed to start validation ritual: %w", err)
	}

	if !outputJSON {
		fmt.Fprintf(os.Stderr, "Ritual started: %s\n", runID)
	}

	if !waitForResults {
		fmt.Printf(`{"runId":"%s","status":"started"}`, runID)
		fmt.Println()
		return nil
	}

	// Wait for completion (with or without streaming)
	var envelope map[string]interface{}

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
			return fmt.Errorf("streaming validation failed: %w", err)
		}
	} else {
		// Use polling (legacy mode)
		if !outputJSON {
			fmt.Fprintf(os.Stderr, "Waiting for results...\n")
		}

		envelope, err = demonClient.WaitForRitual(runID, timeout)
		if err != nil {
			return fmt.Errorf("validation failed: %w", err)
		}
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
