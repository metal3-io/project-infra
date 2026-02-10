# Metal3 Project Infrastructure - AI Agent Instructions

Instructions for AI coding agents.

## Overview

CI/CD infrastructure for Metal3 projects: Jenkins job definitions, Prow
configurations, and CI images. Manages automation for testing, building,
and releasing Metal3 components.

## Repository Structure

| Directory | Purpose |
|-----------|---------|
| `jenkins/jobs/` | Jenkins job definitions (Groovy DSL) |
| `jenkins/scripts/` | Shell scripts used by Jenkins jobs |
| `jenkins/image_building/` | DIB elements for node images |
| `prow/config/` | Prow configuration and job definitions |
| `hack/` | Utility scripts (linters, test dumper) |

## Testing Standards

Run locally before PRs:

| Command | Purpose |
|---------|---------|
| `./hack/shellcheck.sh` | Shell script linting |
| `./hack/markdownlint.sh` | Markdown linting |
| `./hack/spellcheck.sh` | Spell checking |
| `cd prow && make validate` | Validate Prow config |

## Code Conventions

- **Groovy**: Jenkins job DSL in `jenkins/jobs/*.groovy`
- **Shell**: Use `set -eux` in scripts
- **YAML**: Prow configs validated by checkconfig

## Key Workflows

### Adding Jenkins Job

1. Create/edit `.groovy` file in `jenkins/jobs/`
1. Follow existing job naming: `metal3-{frequency}-{os}-{test}-{branch}`
1. Run `./hack/shellcheck.sh` for any shell scripts

### Modifying Prow Config

1. Edit files in `prow/config/`
1. Run `cd prow && make validate`
1. Changes apply on merge to main

## Code Review Guidelines

When reviewing pull requests:

1. **Impact** - CI changes affect all Metal3 repos
1. **Testing** - Validate configs before merge
1. **Consistency** - Follow existing job patterns
1. **Branch coverage** - Update release branch jobs too

Focus on: `jenkins/jobs/`, `prow/config/`, `jenkins/scripts/`.

## AI Agent Guidelines

1. Run linters before committing
1. Validate Prow changes with `cd prow && make validate`
1. Follow existing Groovy job patterns
1. Update `.cspell-config.json` for new terms

## Integration

- **Jenkins**: <https://jenkins.nordix.org/>
- **JJB definitions**: [Nordix cicd repo](https://gerrit.nordix.org/gitweb?p=infra/cicd.git;a=tree;f=jjb/metal3)
  at `jjb/metal3/`
- Jobs triggered by PRs in Metal3 repos
- Uses [metal3-dev-env](https://github.com/metal3-io/metal3-dev-env)
  for e2e tests

## Related Documentation

- [Jenkins README](jenkins/README.md)
- [Prow README](prow/README.md)
