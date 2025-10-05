package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var (
	demonURL   string
	demonToken string
	outputJSON bool
)

var rootCmd = &cobra.Command{
	Use:   "hossctl",
	Short: "HOSS CLI for Demon App Pack",
	Long: `hossctl is the command-line interface for the HOSS App Pack.
It interacts with Demon platform APIs to run fabric validation rituals.

Environment Variables:
  DEMON_URL    Demon API endpoint (default: http://localhost:8080)
  DEMON_TOKEN  Authentication token for Demon API (optional)`,
	Version: "0.1.0",
}

func Execute() error {
	return rootCmd.Execute()
}

func init() {
	cobra.OnInitialize(initConfig)

	rootCmd.PersistentFlags().StringVar(&demonURL, "demon-url", "", "Demon API endpoint")
	rootCmd.PersistentFlags().StringVar(&demonToken, "demon-token", "", "Demon API authentication token")
	rootCmd.PersistentFlags().BoolVar(&outputJSON, "json", false, "Output in JSON format")

	viper.BindPFlag("demon.url", rootCmd.PersistentFlags().Lookup("demon-url"))
	viper.BindPFlag("demon.token", rootCmd.PersistentFlags().Lookup("demon-token"))

	viper.SetDefault("demon.url", "http://localhost:8080")
}

func initConfig() {
	viper.SetEnvPrefix("DEMON")
	viper.AutomaticEnv()

	if demonURL == "" {
		demonURL = viper.GetString("demon.url")
		if demonURL == "" {
			demonURL = "http://localhost:8080"
		}
	}

	if demonToken == "" {
		demonToken = viper.GetString("demon.token")
	}
}

func getDemonURL() string {
	if demonURL != "" {
		return demonURL
	}
	if url := os.Getenv("DEMON_URL"); url != "" {
		return url
	}
	return "http://localhost:8080"
}

func getDemonToken() string {
	if demonToken != "" {
		return demonToken
	}
	return os.Getenv("DEMON_TOKEN")
}

func printJSON(data interface{}) error {
	fmt.Println(data)
	return nil
}

func printError(msg string) {
	fmt.Fprintf(os.Stderr, "Error: %s\n", msg)
}
