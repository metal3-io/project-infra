// Global variables
def TIMEOUT = 1800, ci_git_url, ci_git_branch, ci_git_base, refspec
def UPDATED_REPO, agent_label, BUILD_TAG, GINKGO_SKIP, CURRENT_START_TIME, CURRENT_END_TIME

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

    if ( "${GINKGO_FOCUS}" == 'integration' ) {
        agent_label = "metal3ci-8c16gb-${IMAGE_OS}"
  } else if ( "${GINKGO_FOCUS}" == 'k8s-upgrade' ) {
        agent_label = "metal3ci-8c24gb-${IMAGE_OS}"
    }
}

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
        PRE_RELEASE = 'true' // Affects the way k8s is installed in node image building
        IMAGE_TYPE = 'node'
        KUBERNETES_VERSION = 'v1.34.1' // base version, the pre-release version will be fetched automatically
        CRICTL_VERSION = "${CRICTL_VERSION}"
        CRIO_VERSION = "${CRIO_VERSION}"
        CAPM3RELEASEBRANCH = "${capm3_release_branch}"
        BMORELEASEBRANCH = "${bmo_release_branch}"
        CAPI_VERSION = "${CAPI_VERSION}"
        CAPM3_VERSION = "${CAPM3_VERSION}"
        GINKGO_FOCUS = "${GINKGO_FOCUS}"
        GINKGO_SKIP = "${GINKGO_SKIP}"
        NUM_NODES = "${NUM_NODES}"
        TARGET_NODE_MEMORY = "${TARGET_NODE_MEMORY}"
        KUBERNETES_VERSION_UPGRADE_FROM = "${KUBERNETES_VERSION_UPGRADE_FROM}"
    }
    stages {
        stage('Checkout CI Repo') {
            options {
                timeout(time: 5, unit: 'MINUTES')
            }
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: ci_git_branch]],
                    doGenerateSubmoduleConfigurations: false,
                    extensions: [
                        [$class: 'WipeWorkspace'],
                        [$class: 'CleanCheckout'],
                        [$class: 'CleanBeforeCheckout']
                    ],
                    submoduleCfg: [],
                    userRemoteConfigs: [[url: ci_git_url, refspec: refspec]]
                ])
            }
        }
        stage('Build disk image') {
            options {
                timeout(time: 1, unit: 'HOURS')
            }
            steps {
                echo "Building ${IMAGE_OS} node image"
                script {
                    sh './jenkins/image_building/build-image.sh'
                }
            }
        }
        stage('Run e2e tests') {
            options {
                timeout(time: 3, unit: 'HOURS')
            }
            steps {
                script {
                    CURRENT_START_TIME = System.currentTimeMillis()

                    // Set image name and location and used k8s version as env variables
                    // to use the local image in the testing
                    def imgName = readFile('image_name.txt').trim()
                    def k8sVersion = imgName.split('_').last()

                    env.IMAGE_NAME = "${imgName}.qcow2"
                    env.IMAGE_LOCATION = env.WORKSPACE
                    env.KUBERNETES_VERSION_UPGRADE_TO = k8sVersion

                    echo "Set IMAGE_NAME to: ${env.IMAGE_NAME}"
                    echo "Set IMAGE_LOCATION to: ${env.IMAGE_LOCATION}"
                    echo "Set KUBERNETES_VERSION_UPGRADE_TO to: ${env.KUBERNETES_VERSION_UPGRADE_TO}"
                }
                echo "Testing with the new ${IMAGE_OS} node image"
                withEnv(["KUBERNETES_VERSION=${readFile('image_name.txt').trim().split('_').last()}"]) {
                    echo "Set KUBERNETES_VERSION to: ${env.KUBERNETES_VERSION}"
                    withCredentials([string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN')]) {
                        ansiColor('xterm') {
                            timestamps {
                                sh './jenkins/scripts/dynamic_worker_workflow/e2e_tests.sh'
                            }
                        }
                    }
                }
            }
            post {
                always {
                    script {
                        CURRENT_END_TIME = System.currentTimeMillis()
                        if ((((CURRENT_END_TIME - CURRENT_START_TIME) / 1000) - 10800) > 0) {
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
}
