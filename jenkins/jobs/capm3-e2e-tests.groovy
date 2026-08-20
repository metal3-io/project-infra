// Global variables
// Set default TIMEOUT to 10800 (3h)
def TIMEOUT = 10800, ci_git_url, ci_git_branch, ci_git_base, refspec, agent_label
def UPDATED_REPO, BUILD_TAG, GINKGO_SKIP, CURRENT_START_TIME, CURRENT_END_TIME, GRAFANA_VIEW
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
    echo "Checkout ${ci_git_url} branch ${ci_git_branch}"

    if ( "${GINKGO_FOCUS}" == 'integration' || "${GINKGO_FOCUS}" == 'basic' ) {
        agent_label = "metal3ci-8c32gb-${IMAGE_OS}-oci"
        TIMEOUT = 10800 // 3h
  } else if ( "${GINKGO_FOCUS}" == 'pivoting' ) {
        BUILD_TAG = "${env.BUILD_TAG}-pivoting-based"
        TIMEOUT = 18000 // 5h for node reuse
        agent_label = "metal3ci-8c32gb-${IMAGE_OS}-oci"
  } else if ( "${GINKGO_FOCUS}" == 'remediation' ) {
        BUILD_TAG = "${env.BUILD_TAG}-remediation-based"
        TIMEOUT = 18000 // 5h for remediation
        agent_label = "metal3ci-8c32gb-${IMAGE_OS}-oci"
  } else if ( "${GINKGO_FOCUS}" == 'k8s-upgrade' ) {
        agent_label = "metal3ci-8c32gb-${IMAGE_OS}-oci"
        TIMEOUT = 14400 // 4h
  } else if ( "${GINKGO_FOCUS}" == 'k8s-upgrade-n3' || "${GINKGO_FOCUS}" == 'scalability' ) {
        agent_label = "metal3ci-8c32gb-${IMAGE_OS}-oci"
        TIMEOUT = 18000 // 5h
  } else if ( "${GINKGO_FOCUS}" == 'k8s-conformance' ) {
        TIMEOUT = 7200 // 2h
        agent_label = "metal3ci-8c32gb-${IMAGE_OS}-oci"
  } else if ( "${GINKGO_FOCUS}" == 'capi-md-tests') {
        TIMEOUT = 10800 // 3h
        agent_label = "metal3ci-8c32gb-${IMAGE_OS}-oci"
  } else {
        agent_label = "metal3ci-8c32gb-${IMAGE_OS}-oci"
        BUILD_TAG = "${env.BUILD_TAG}-other-features"
        GINKGO_SKIP = 'pivoting remediation' // Allow non pivoting features
    }
}

def START_TIME = currentBuild.getStartTimeInMillis()
GRAFANA_VIEW = """${LOG_URL}&from=${START_TIME}&to=now&var-pipeline=${env.JOB_NAME}&var-build=${BUILD_NUMBER}"""
currentBuild.description = """<a href='${GRAFANA_VIEW}'>View in log collector</a>"""

pipeline {
    agent { label agent_label }
    environment {
        REPO_ORG = "${env.REPO_OWNER}"
        REPO_NAME = "${env.REPO_NAME}"
        UPDATED_REPO = "${UPDATED_REPO}"
        REPO_BRANCH = "${env.PULL_BASE_REF ?: capm3_release_branch}"
        UPDATED_BRANCH = "${env.PULL_PULL_SHA ?: capm3_release_branch}"
        BUILD_TAG = "${env.BUILD_TAG}"
        PR_ID = "${env.PULL_NUMBER ?: ''}"
        IMAGE_OS = "${IMAGE_OS}"
        CAPM3RELEASEBRANCH = "${capm3_release_branch}"
        BMORELEASEBRANCH = "${bmo_release_branch}"
        GINKGO_FOCUS = "${GINKGO_FOCUS}"
        GINKGO_SKIP = "${GINKGO_SKIP}"
        NUM_NODES = "${NUM_NODES}"
        CAPI_VERSION = "${CAPI_VERSION}"
        CAPM3_VERSION = "${CAPM3_VERSION}"
        KUBERNETES_VERSION_UPGRADE_FROM = "${KUBERNETES_VERSION_UPGRADE_FROM}"
        KUBERNETES_VERSION_UPGRADE_TO = "${KUBERNETES_VERSION_UPGRADE_TO}"
        KUBERNETES_N0_VERSION = "${KUBERNETES_N0_VERSION}"
        KUBERNETES_N1_VERSION = "${KUBERNETES_N1_VERSION}"
        KUBERNETES_N2_VERSION = "${KUBERNETES_N2_VERSION}"
        KUBERNETES_N3_VERSION = "${KUBERNETES_N3_VERSION}"
        CNI_NAME = "${CNI_NAME}"
    }

    stages {
        stage('e2e test') {
            options {
                timeout(time: TIMEOUT, unit: 'SECONDS')
            }
            steps {
                script {
                    CURRENT_START_TIME = System.currentTimeMillis()
                }
                /* Checkout CI Repo */
                deleteDir()
                checkout([
                  $class: 'GitSCM',
                  branches: [
                    [name: ci_git_branch]
                    ],
                  doGenerateSubmoduleConfigurations: false,
                  extensions: [
                      [$class: 'CleanCheckout'],
                      [$class: 'CleanBeforeCheckout']
                      ],
                  submoduleCfg: [],
                  userRemoteConfigs: [[url: ci_git_url, refspec: refspec]]
                  ])
                withCredentials([string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN'),
                    usernamePassword(credentialsId: 'metal3-ci-log-collector-push', usernameVariable: 'LOKI_USERNAME', passwordVariable: 'LOKI_PASSWORD')]) {
                    ansiColor('xterm') {
                        timestamps {
                            sh './jenkins/scripts/dynamic_worker_workflow/e2e_tests.sh'
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
