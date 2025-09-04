package main

import (
	"fmt"
	"os"

	"github.com/astrago/chart-sync/internal/cmd"
	"github.com/spf13/cobra"
)

var (
	version = "1.0.0"
	rootCmd = &cobra.Command{
		Use:   "chart-sync",
		Short: "Astrago Helm Charts Synchronization Tool",
		Long: `A tool for downloading and managing external Helm charts for offline deployment.
Supports airgap environments by downloading all dependencies locally.`,
		Version: version,
	}
)

func init() {
	rootCmd.AddCommand(cmd.SyncCmd())
	rootCmd.AddCommand(cmd.CleanCmd())
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}