package cmd

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
)

// CleanCmd creates the clean command
func CleanCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "clean",
		Short: "Remove downloaded charts",
		Long:  "Removes all downloaded charts",
		RunE:  runClean,
	}
}

func runClean(cmd *cobra.Command, args []string) error {
	chartsDir, _ := filepath.Abs("../charts/external")
	
	fmt.Println("⚠️  All downloaded charts will be removed.")
	fmt.Print("Do you want to continue? (y/N): ")

	reader := bufio.NewReader(os.Stdin)
	response, err := reader.ReadString('\n')
	if err != nil {
		return fmt.Errorf("failed to read response: %w", err)
	}

	response = strings.TrimSpace(strings.ToLower(response))
	if response != "y" && response != "yes" {
		fmt.Println("🚫 Cancelled.")
		return nil
	}

	// Remove charts directory
	if err := os.RemoveAll(chartsDir); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to remove charts directory: %w", err)
	}

	fmt.Println("✅ All charts have been removed.")
	return nil
}