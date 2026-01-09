def TIMEOUT = 10800, CURRENT_START_TIME, CURRENT_END_TIME
// Set defaults for non-PR jobs
def pullSha = (env.PULL_PULL_SHA) ?: 'main'
def pullBase = (env.PULL_BASE_REF) ?: 'main'
def repoUrl = 'https://github.com/metal3-io/baremetal-operator.git'
// Fetch the base branch and the pullSha, nothing else
def refspec = '+refs/heads/' + pullBase + ':refs/remotes/origin/' + pullBase + ' ' + pullSha

pipeline {
    environment {
        GINKGO_FOCUS = "${GINKGO_FOCUS}"
    }
    agent none
    stages {
        stage('Run Baremetal Operator optional e2e tests') {
            matrix {
                agent { label 'metal3ci-8c16gb-ubuntu' }
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
                            checkout scmGit(
                  branches: [[name: pullSha]],
                  userRemoteConfigs: [[url: repoUrl, refspec: refspec]],
                  extensions: [[$class: 'WipeWorkspace'],
                  [$class: 'CleanCheckout'],
                  [$class: 'CleanBeforeCheckout'],
                  [$class: 'PreBuildMerge', options: [mergeTarget: pullBase, mergeRemote: 'origin']],
                  [$class: 'UserIdentity', name: 'Test', email: 'test@test.test'],
                  cloneOption(honorRefspec: true)],
                  submoduleCfg: [],)
                            script {
                                CURRENT_START_TIME = System.currentTimeMillis()
                            }
                        }
                    }
                    stage('Run Baremetal Operator optional e2e test') {
                        options {
                            timeout(time: TIMEOUT, unit: 'SECONDS')
                            ansiColor('xterm')
                        }
                        steps {
                            withCredentials([string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN')]) {
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
            }
        }
    }
}
