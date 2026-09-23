// Set defaults for non-PR jobs
def pullSha = (env.PULL_PULL_SHA) ?: 'main'
def pullBase = (env.PULL_BASE_REF) ?: 'main'
def repoUrl = 'https://github.com/metal3-io/baremetal-operator.git'
// Fetch the base branch and the pullSha, nothing else
def refspec = '+refs/heads/' + pullBase + ':refs/remotes/origin/' + pullBase + ' ' + pullSha

pipeline {
    agent { label 'metal3ci-8c32gb-ubuntu-oci' }
    environment {
        E2E_CONF_FILE = "${WORKSPACE}/test/e2e/config/fixture.yaml"
        GINKGO_NODES = '1'
        IMG = 'quay.io/metal3-io/baremetal-operator'
        IMG_TAG = 'e2e'
    }
    stages {
        stage('Checkout source code') {
            steps {
                deleteDir()
                checkout scmGit(
                    branches: [[name: pullSha]],
                    userRemoteConfigs: [[url: repoUrl, refspec: refspec]],
                    extensions: [[$class: 'CleanCheckout'],
                    [$class: 'CleanBeforeCheckout'],
                    [$class: 'PreBuildMerge', options: [mergeTarget: pullBase, mergeRemote: 'origin']],
                    cloneOption(honorRefspec: true)],
                )
            }
        }
        stage('Run Baremetal Operator e2e fixture test') {
            options {
                timeout(time: 1800, unit: 'SECONDS')
                ansiColor('xterm')
            }
            steps {
                timestamps {
                    sh 'make docker'
                    sh 'make test-e2e'
                }
            }
            post {
                always {
                    archiveArtifacts 'test/e2e/_artifacts/**'
                }
            }
        }
    }
}
