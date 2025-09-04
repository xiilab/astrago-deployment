package helm

import (
	"fmt"
	"os"

	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/cli"
	"helm.sh/helm/v3/pkg/getter"
	"helm.sh/helm/v3/pkg/repo"
)

// Client wraps Helm operations
type Client struct {
	settings *cli.EnvSettings
	config   *action.Configuration
}

// NewClient creates a new Helm client
func NewClient() (*Client, error) {
	settings := cli.New()
	config := new(action.Configuration)
	
	// Initialize with no namespace (we're only downloading charts)
	if err := config.Init(settings.RESTClientGetter(), "", os.Getenv("HELM_DRIVER"), debugLog); err != nil {
		return nil, fmt.Errorf("failed to initialize Helm config: %w", err)
	}

	return &Client{
		settings: settings,
		config:   config,
	}, nil
}

func debugLog(format string, v ...interface{}) {
	if os.Getenv("HELM_DEBUG") == "true" {
		fmt.Printf(format+"\n", v...)
	}
}

// AddRepository adds a Helm repository
func (c *Client) AddRepository(name, url string) error {
	repoFile := c.settings.RepositoryConfig

	// Load existing repositories
	f, err := repo.LoadFile(repoFile)
	if os.IsNotExist(err) {
		f = repo.NewFile()
	} else if err != nil {
		return fmt.Errorf("failed to load repo file: %w", err)
	}

	// Check if repo already exists
	if f.Has(name) {
		fmt.Printf("Repository %s already exists, updating...\n", name)
	}

	// Create repo entry
	entry := &repo.Entry{
		Name: name,
		URL:  url,
	}

	// Get chart repository
	r, err := repo.NewChartRepository(entry, getter.All(c.settings))
	if err != nil {
		return fmt.Errorf("failed to create chart repository: %w", err)
	}

	// Download and update the index
	if _, err := r.DownloadIndexFile(); err != nil {
		return fmt.Errorf("failed to download repository index: %w", err)
	}

	// Update or add the repository
	f.Update(entry)

	// Save the repository file
	if err := f.WriteFile(repoFile, 0644); err != nil {
		return fmt.Errorf("failed to write repo file: %w", err)
	}

	return nil
}

// UpdateRepositories updates all configured repositories
func (c *Client) UpdateRepositories() error {
	repoFile := c.settings.RepositoryConfig

	f, err := repo.LoadFile(repoFile)
	if err != nil {
		return fmt.Errorf("failed to load repo file: %w", err)
	}

	for _, entry := range f.Repositories {
		r, err := repo.NewChartRepository(entry, getter.All(c.settings))
		if err != nil {
			return fmt.Errorf("failed to create chart repository for %s: %w", entry.Name, err)
		}

		if _, err := r.DownloadIndexFile(); err != nil {
			return fmt.Errorf("failed to update repository %s: %w", entry.Name, err)
		}
	}

	return nil
}

// DownloadChart downloads a chart to the specified directory
func (c *Client) DownloadChart(repoName, chartName, version, destDir string) error {
	// Create pull client
	pull := action.NewPullWithOpts(action.WithConfig(c.config))
	pull.Settings = c.settings
	pull.Version = version
	pull.Untar = true
	pull.UntarDir = destDir

	// Create full chart reference
	chartRef := fmt.Sprintf("%s/%s", repoName, chartName)

	// Download the chart
	output, err := pull.Run(chartRef)
	if err != nil {
		return fmt.Errorf("failed to download chart %s:%s: %w", chartRef, version, err)
	}

	fmt.Printf("Downloaded: %s\n", output)
	return nil
}

