// Global variables
def TIMEOUT = 10800, ci_git_url, ci_git_branch, ci_git_base, refspec, agent_label
def UPDATED_REPO, CURRENT_START_TIME, CURRENT_END_TIME, GRAFANA_VIEW
def LOG_URL = 'https://log.apps.test.metal3.io/view/?orgId=1&timezone=browser&kiosk'

script {
    UPDATED_REPO = "https://github.com/${env.REPO_OWNER}/${env.REPO_NAME}.git"
    echo "Test triggered from ${UPDATED_REPO}"
    ci_git_url = 'https://github.com/metal3-io/project-infra.git'

    if ("${env.REPO_OWNER}" == 'metal3-io' && "${env.REPO_NAME}" == 'project-infra') {
        ci_git_branch = (env.PULL_PULL_SHA) ?: 'main'
        ci_git_base = (env.PULL_BASE_REF) ?: 'main'
        // Fetch the base branch and the ci_git_branch when running on project-infra PR
        refspec = '+refs/heads/' + ci_git_base + ':refs/remotes/origin/' + ci_git_base + ' ' + ci_git_branch
  } else {
        ci_git_branch = 'main'
        refspec = '+refs/heads/*:refs/remotes/origin/*'
    }
    agent_label = "metal3ci-8c32gb-${IMAGE_OS}-oci"
}

def START_TIME = currentBuild.getStartTimeInMillis()
GRAFANA_VIEW = """${LOG_URL}&from=${START_TIME}&to=now&var-pipeline=${env.JOB_NAME}&var-build=${BUILD_NUMBER}"""
currentBuild.description = """<a href='${GRAFANA_VIEW}'>View in log collector</a>"""

pipeline {
    agent { label agent_label }
    environment {
        REPO_ORG = "${env.REPO_OWNER}"
        REPO_NAME = "${env.REPO_NAME}"
        REPO_BRANCH = "${env.PULL_BASE_REF}"
        UPDATED_REPO = "${UPDATED_REPO}"
        UPDATED_BRANCH = "${env.PULL_PULL_SHA}"
        BUILD_TAG = "${env.BUILD_TAG}"
        PR_ID = "${env.PULL_NUMBER}"
        IMAGE_OS = "${params.IMAGE_OS}"
        IPXE_TLS_PORT = "${params.IPXE_TLS_PORT}"
        TLS_VERSION = "${params.TLS_VERSION}"
        NUM_NODES = "${params.NUM_NODES}"
    }

    stages {
        stage('Run iPXE TLS provisioning test') {
            options {
                timeout(time: TIMEOUT, unit: 'SECONDS')
            }
            environment {
                BUILD_TAG = "${env.BUILD_TAG}-ipxe-tls-provision"
            }
            steps {
                script {
                    CURRENT_START_TIME = System.currentTimeMillis()
                }
                /* Checkout CI Repo */
                deleteDir()
                checkout([$class: 'GitSCM',
                  branches: [
                    [name: ci_git_branch]
                  ],
                  doGenerateSubmoduleConfigurations: false,
                  userRemoteConfigs: [[url: ci_git_url, refspec: refspec, credentialsId: 'metal3-clusterctl-github-token']]
                ])
                withCredentials([string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN')]) {
                    ansiColor('xterm') {
                        timestamps {
                            sh './jenkins/scripts/dynamic_worker_workflow/ipxe_tls_provision_test.sh'
                        }
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
                        timestamps {
                            sh './jenkins/scripts/dynamic_worker_workflow/fetch_logs.sh'
                            archiveArtifacts "logs-${env.BUILD_TAG}.tgz"
                        }
                    }
                }
                cleanup {
                    script {
                        timestamps {
                            sh './jenkins/scripts/dynamic_worker_workflow/run_clean.sh'
                        }
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
