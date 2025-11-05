# Project Infrastructure - AI Coding Assistant Instructions

## Project Overview

This repository contains CI/CD infrastructure configuration for Metal3
projects including Jenkins job definitions, Prow configurations, and
utility images. Manages the automation pipeline that tests, builds, and
releases Metal3 components.

## Key Components

### Jenkins (jenkins/)

- Job DSL definitions for periodic and PR-triggered tests
- E2E integration tests across Ubuntu, CentOS, OpenSUSE
- Feature-specific test jobs (pivoting, remediation, upgrades)
- Image building pipelines

### Prow (prow/)

- Kubernetes-native CI/CD for GitHub automation
- PR validation, labeling, merging automation
- Test result reporting and metrics

### Image Building (jenkins/image_building/)

- DIB (diskimage-builder) elements for test images
- Custom Ubuntu, CentOS node images
- CI container images for test infrastructure

## Jenkins Job Structure

Jobs follow naming pattern: `metal3-{frequency}-{os}-{test-type}-{branch}`

Examples:

- `metal3-periodic-ubuntu-e2e-integration-test-main`
- `metal3-centos-e2e-feature-test-main-pivoting`
- `metal3-periodic-centos-e2e-integration-test-release-1-11`

## Key Files

- `jenkins/jobs/` - Jenkins job configurations (Groovy DSL)
- `prow/config.yaml` - Prow configuration
- `prow/plugins.yaml` - Prow plugin configuration
- `jenkins/image_building/dib_elements/` - Diskimage builder elements

## Usage

Most developers don't modify this directly - CI jobs are triggered automatically:

**PR Testing:**

- Comment `/test <job-name>` to trigger specific test
- Comment `/retest` to rerun failed tests

**Monitoring:**

- Jenkins dashboard: <https://jenkins.nordix.org/>
- Check build status badges in project READMEs

## Development

**Adding a New Test Job:**

1. Create job DSL in `jenkins/jobs/`
2. Define job parameters, triggers, build steps
3. Test locally with Jenkins Job DSL plugin
4. Submit PR to this repo

**Modifying Prow Config:**

1. Edit `prow/config.yaml` or `prow/plugins.yaml`
2. Validate with Prow checkconfig tool
3. Changes applied on merge to main

## Common Pitfalls

1. **Job Dependencies** - Ensure required infrastructure (libvirt,
   networks) configured
2. **Resource Limits** - Jenkins nodes have finite resources, jobs may
   queue
3. **Flaky Tests** - Transient failures require investigation and retry
   logic
4. **Branch Maintenance** - Keep release branch jobs in sync with main

This repo is primarily for Metal3 maintainers managing CI/CD
infrastructure. Most contributors interact via PR comments and status
checks.
