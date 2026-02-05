/*
Copyright 2025 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

		http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"regexp"
	"strings"

	"github.com/blang/semver"
	"github.com/google/go-github/github"
	"golang.org/x/oauth2"
)

/*
This tool prints all the titles of all PRs from previous release to HEAD.
This needs to be run *before* a tag is created.

Use these as the base of your release notes.
*/

const (
	features        = ":sparkles: New Features"
	bugs            = ":bug: Bug Fixes"
	documentation   = ":book: Documentation"
	warning         = ":warning: Breaking Changes"
	other           = ":seedling: Others"
	unknown         = ":question: Sort these by hand"
	superseded      = ":recycle: Superseded or Reverted"
	warningTemplate = ":rotating_light: This is a %s. Use it only for testing purposes.\nIf you find any bugs, file an [issue](https://github.com/%s/%s/issues/new/).\n\n"
)

var (
	outputOrder = []string{
		warning,
		features,
		bugs,
		documentation,
		other,
		unknown,
		superseded,
	}
	releaseTag     string
	repoOwner      string
	repoName       string
	semVersion     semver.Version
	lastReleaseTag string
)

func main() {
	releaseTag = os.Getenv("RELEASE_TAG")
	if releaseTag == "" {
		log.Fatal("RELEASE_TAG is required")
	}
	repoOwner = os.Getenv("REPO_OWNER")
	if repoOwner == "" {
		log.Fatal("REPO_OWNER is required")
	}
	repoName = os.Getenv("REPO_NAME")
	if repoName == "" {
		log.Fatal("REPO_NAME is required")
	}

	// Create a context
	ctx := context.Background()

	// Authenticate with GitHub token if available
	token := os.Getenv("GITHUB_TOKEN")
	var client *github.Client
	if token != "" {
		ts := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: token})
		tc := oauth2.NewClient(ctx, ts)
		client = github.NewClient(tc)
	} else {
		client = github.NewClient(nil)
	}
	releaseName := strings.TrimPrefix(releaseTag, "v")
	var err error
	semVersion, err = semver.Make(releaseName)
	if err != nil {
		log.Fatalf("Incorrect releaseTag: %v", err)
	}

	// Get the name of the release branch. Default to "main" if it's a minor release
	releaseBranch := fmt.Sprintf("release-%d.%d", semVersion.Major, semVersion.Minor)
	if semVersion.Patch == 0 {
		releaseBranch = "main"
	}

	// Get the release tag used for comparison
	lastVersion := semVersion
	if lastVersion.Patch == 0 {
		lastVersion.Minor--
	} else {
		lastVersion.Patch--
	}
	lastReleaseTag = fmt.Sprintf("v%d.%d.%d", lastVersion.Major, lastVersion.Minor, lastVersion.Patch)

	// Compare commits between the tag and the release branch
	comparison, _, err := client.Repositories.CompareCommits(ctx, repoOwner, repoName, lastReleaseTag, releaseBranch)
	if err != nil {
		log.Fatalf("failed to compare commits: %v", err)
	}
	merges := map[string][]string{
		features:      {},
		bugs:          {},
		documentation: {},
		warning:       {},
		other:         {},
		unknown:       {},
		superseded:    {},
	}

	for _, commit := range comparison.Commits {
		// Only takes the merge commits.
		if len(commit.Parents) == 1 {
			continue
		}
		mergeCommitRegex := regexp.MustCompile(`Merge pull request #(\d+) from`)
		matches := mergeCommitRegex.FindStringSubmatch(commit.GetCommit().GetMessage())
		var prNumber string
		if len(matches) > 1 {
			// This is a merge commit, extract the PR number
			prNumber = matches[1]
		}

		// Append commit message and PR number
		lines := strings.Split(commit.GetCommit().GetMessage(), "\n")
		body := lines[len(lines)-1]
		if body == "" {
			continue
		}
		var key string
		switch {
		case strings.HasPrefix(body, ":sparkles:"), strings.HasPrefix(body, "✨"):
			key = features
			body = strings.TrimPrefix(body, ":sparkles:")
			body = strings.TrimPrefix(body, "✨")
		case strings.HasPrefix(body, ":bug:"), strings.HasPrefix(body, "🐛"):
			key = bugs
			body = strings.TrimPrefix(body, ":bug:")
			body = strings.TrimPrefix(body, "🐛")
		case strings.HasPrefix(body, ":book:"), strings.HasPrefix(body, "📖"):
			key = documentation
			body = strings.TrimPrefix(body, ":book:")
			body = strings.TrimPrefix(body, "📖")
		case strings.HasPrefix(body, ":seedling:"), strings.HasPrefix(body, "🌱"):
			key = other
			body = strings.TrimPrefix(body, ":seedling:")
			body = strings.TrimPrefix(body, "🌱")
		case strings.HasPrefix(body, ":warning:"), strings.HasPrefix(body, "⚠️"):
			key = warning
			body = strings.TrimPrefix(body, ":warning:")
			body = strings.TrimPrefix(body, "⚠️")
		case strings.HasPrefix(body, ":rocket:"), strings.HasPrefix(body, "🚀"):
			continue
		default:
			key = unknown
		}
		merges[key] = append(merges[key], fmt.Sprintf("- %s (#%d)", body, prNumber))
	}
	fmt.Println("<!-- markdownlint-disable no-inline-html line-length -->")
	// if we're doing beta/rc, print breaking changes and hide the rest of the changes
	if len(semVersion.Pre) > 0 {
		switch semVersion.Pre[0].VersionStr {
		case "beta":
			fmt.Printf(warningTemplate, "BETA RELEASE", repoOwner, repoName)
		case "rc":
			fmt.Printf(warningTemplate, "RELEASE CANDIDATE", repoOwner, repoName)
		}
		fmt.Printf("<details>\n")
		fmt.Printf("<summary>More details about the release</summary>\n\n")
	}
	fmt.Printf("# Changes since [%s](https://github.com/%s/%s/tree/%s)\n\n", lastReleaseTag, repoOwner, repoName, lastReleaseTag)
	// print the changes by category
	for _, key := range outputOrder {
		mergeslice := merges[key]
		if len(mergeslice) > 0 {
			fmt.Printf("## %v\n\n", key)
			for _, merge := range mergeslice {
				fmt.Println(merge)
			}
			fmt.Println()
		}
	}

	// close the details tag if we had it open, else add the Superseded or Reverted section
	if len(semVersion.Pre) > 0 {
		fmt.Printf("</details>\n\n")
	} else {
		fmt.Println("\n## :recycle: Superseded or Reverted")
	}

	fmt.Printf("The container image for this release is: %s\n", releaseTag)
	if repoName == "cluster-api-provider-metal3" {
		fmt.Printf("Mariadb image tag is: capm3-%s\n", releaseTag)
	}
	fmt.Println("\n_Thanks to all our contributors!_ 😊")
}
