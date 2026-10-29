def TIMEOUT = 10800, CURRENT_START_TIME, CURRENT_END_TIME, GRAFANA_VIEW
def LOG_URL = 'https://log.apps.test.metal3.io/view/?orgId=1&timezone=browser&kiosk'
// Set defaults for non-PR jobs
def pullSha = (env.PULL_PULL_SHA) ?: 'main'
def pullBase = (env.PULL_BASE_REF) ?: 'main'
def repoUrl = 'https://github.com/metal3-io/baremetal-operator.git'
// Fetch the base branch and the pullSha, nothing else
def refspec = '+refs/heads/' + pullBase + ':refs/remotes/origin/' + pullBase + ' ' + pullSha
// Dynamic build info generation
// In matrix jobs "axis" have their individual start and finish times.
// Global "build" start time has to be determined before the matrix is
// constructed
def START_TIME = currentBuild.getStartTimeInMillis()
GRAFANA_VIEW = """${LOG_URL}&from=${START_TIME}&to=now&var-pipeline=${env.JOB_NAME}&var-build=${BUILD_NUMBER}"""
currentBuild.description = """<a href='${GRAFANA_VIEW}'>View in log collector</a>"""

pipeline {
    environment {
        // Selects the upgrade tier of the BMO e2e suite. See
        // test/e2e/README.md in the baremetal-operator repository.
        GINKGO_LABEL_FILTER = 'upgrade'
        // The upgrade specs create their own clusters and deploy their own
        // Ironic/BMO/cert-manager, so the shared stack must not be deployed
        // for them. hack/ci-e2e.sh does this for the upgrade tier as well,
        // but only on branches that have the tier split. Setting it here
        // keeps the job correct against older branches too.
        DEPLOY_IRONIC = 'false'
        DEPLOY_BMO = 'false'
        DEPLOY_CERT_MANAGER = 'false'
        // Each upgrade spec brings up its own kind cluster, so they are not
        // run in parallel.
        GINKGO_NODES = '1'
        LOKI_URL = 'https://log.apps.test.metal3.io/store/api/v1/push'
    }
    agent none
    stages {
        stage('Run Baremetal Operator upgrade e2e tests') {
            matrix {
                agent { label 'metal3ci-8c32gb-ubuntu-oci' }
                axes {
                    axis {
                        name 'BMC_PROTOCOL'
                        values 'ipmi', 'redfish-virtualmedia'
                    }
                }
                environment {
                    BMC_PROTOCOL = "${BMC_PROTOCOL}"
                }
                stages {
                    stage('Checkout source code') {
                        steps {
                            deleteDir()
                            checkout scmGit(
                  branches: [[name: pullSha]],
                  userRemoteConfigs: [[url: repoUrl, refspec: refspec, credentialsId: 'metal3-clusterctl-github-token']],
                  extensions: [
                  [$class: 'PreBuildMerge', options: [mergeTarget: pullBase, mergeRemote: 'origin']],
                  [$class: 'UserIdentity', name: 'Test', email: 'test@test.test'],
                  cloneOption(honorRefspec: true)])
                            script {
                                CURRENT_START_TIME = System.currentTimeMillis()
                            }
                        }
                    }
                    stage('Run Baremetal Operator upgrade e2e test') {
                        options {
                            timeout(time: TIMEOUT, unit: 'SECONDS')
                            ansiColor('xterm')
                        }
                        steps {
                            withCredentials(
                                [string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN'),
                                usernamePassword(credentialsId: 'metal3-ci-log-collector-push',
                                usernameVariable: 'LOKI_USERNAME', passwordVariable: 'LOKI_PASSWORD'),
                            ]) {
                                timestamps {
                                    sh './hack/ci-e2e.sh'
                                }
                            }
                        }
                        post {
                            always {
                                script {
                                    CURRENT_END_TIME = System.currentTimeMillis()
                                    if ((((CURRENT_END_TIME - CURRENT_START_TIME) / 1000) - TIMEOUT) > 0) {
                                        echo 'Failed due to timeout'
                                        currentBuild.result = 'FAILURE'
                                    }
                                }
                                archiveArtifacts 'artifacts*.tar.gz'
                                timestamps {
                                    /* Clean up */
                                    sh 'make clean-e2e'
                                }
                            }
                        }
                    }
                }
                post {
                    always {
                        retire_agent()
                    }
                }
            }
        }
    }
    post {
        always {
            script {
                CURRENT_END_TIME = System.currentTimeMillis()
                // Dynamic build info generation
                GRAFANA_VIEW = """${LOG_URL}&from=${START_TIME}&to=${CURRENT_END_TIME}&var-pipeline=${env.JOB_NAME}&var-build=${BUILD_NUMBER}"""
                currentBuild.description = """<a href='${GRAFANA_VIEW}'>View in log collector</a>"""
            }
        }
    }
}
