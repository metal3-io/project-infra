// Global variables
def TIMEOUT = 14400, ci_git_url, ci_git_branch, ci_git_base, refspec
def CURRENT_START_TIME, CURRENT_END_TIME

script {
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
}

pipeline {
  /* In the BML we always run on the same machine so concurrency must be disabled */
    options {
        disableConcurrentBuilds()
    }
    agent { label 'metal3ci-bml-jenkins-worker' }
    environment {
        METAL3_CI_USER = 'metal3ci'
        BUILD_TAG = "${env.BUILD_TAG}"
        IMAGE_OS = "${IMAGE_OS}"
    }
    stages {
        stage('SCM') {
            options {
                timeout(time: 5, unit: 'MINUTES')
            }
            steps {
            /* Checkout CI Repo */
                checkout([
                    $class: 'GitSCM',
                    branches: [
                        [name: ci_git_branch]
                        ],
                    doGenerateSubmoduleConfigurations: false,
                    extensions: [
                        [$class: 'WipeWorkspace'],
                        [$class: 'CleanCheckout'],
                        [$class: 'CleanBeforeCheckout']
                        ],
                    submoduleCfg: [],
                    userRemoteConfigs: [[url: ci_git_url, refspec: refspec]]
                ])
                script {
                    CURRENT_START_TIME = System.currentTimeMillis()
                }
            }
        }
        stage('Clean up lab before test') {
            options {
                timeout(time: TIMEOUT, unit: 'SECONDS')
            }
            steps {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'metal3ci_city_cloud_ssh_keypair', keyFileVariable: 'METAL3_CI_USER_KEY'),
                    usernamePassword(credentialsId: 'metal3-bml-ilo-credentials', usernameVariable: 'BML_ILO_USERNAME', passwordVariable: 'BML_ILO_PASSWORD'),
                    string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN')]) {
                    timestamps {
                        sh './jenkins/scripts/bare_metal_lab/bml_test.sh clean'
                    }
                }
            }
        }
        stage('Set up management cluster') {
            options {
                timeout(time: TIMEOUT, unit: 'SECONDS')
            }
            steps {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'metal3ci_city_cloud_ssh_keypair', keyFileVariable: 'METAL3_CI_USER_KEY'),
                    usernamePassword(credentialsId: 'metal3-bml-ilo-credentials', usernameVariable: 'BML_ILO_USERNAME', passwordVariable: 'BML_ILO_PASSWORD'),
                    string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN')]) {
                    timestamps {
                        sh './jenkins/scripts/bare_metal_lab/bml_test.sh deploy'
                    }
                }
            }
        }
        stage('Provision target cluster') {
            options {
                timeout(time: TIMEOUT, unit: 'SECONDS')
            }
            steps {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'metal3ci_city_cloud_ssh_keypair', keyFileVariable: 'METAL3_CI_USER_KEY'),
                    usernamePassword(credentialsId: 'metal3-bml-ilo-credentials', usernameVariable: 'BML_ILO_USERNAME', passwordVariable: 'BML_ILO_PASSWORD'),
                    string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN')]) {
                    timestamps {
                        sh './jenkins/scripts/bare_metal_lab/bml_test.sh run-test'
                    }
                }
            }
        }
        stage('Run pod scaling tests') {
            options {
                timeout(time: TIMEOUT, unit: 'SECONDS')
            }
            steps {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'metal3ci_city_cloud_ssh_keypair', keyFileVariable: 'METAL3_CI_USER_KEY'),
                    usernamePassword(credentialsId: 'metal3-bml-ilo-credentials', usernameVariable: 'BML_ILO_USERNAME', passwordVariable: 'BML_ILO_PASSWORD'),
                    string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN')]) {
                    timestamps {
                        sh 'echo "Pod scaling tests are currently disabled"'
                        /* sh './jenkins/scripts/bare_metal_lab/bml_test.sh pod-scale' */
                    }
                }
            }
        }
        stage('Teardown provisioned target cluster after test') {
            options {
                timeout(time: TIMEOUT, unit: 'SECONDS')
            }
            steps {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'metal3ci_city_cloud_ssh_keypair', keyFileVariable: 'METAL3_CI_USER_KEY'),
                    usernamePassword(credentialsId: 'metal3-bml-ilo-credentials', usernameVariable: 'BML_ILO_USERNAME', passwordVariable: 'BML_ILO_PASSWORD'),
                    string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN')]) {
                    timestamps {
                        sh './jenkins/scripts/bare_metal_lab/bml_test.sh teardown'
                    }
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
            }
        }
        success {
            withCredentials([sshUserPrivateKey(credentialsId: 'metal3ci_city_cloud_ssh_keypair', keyFileVariable: 'METAL3_CI_USER_KEY'),
                usernamePassword(credentialsId: 'metal3-bml-ilo-credentials', usernameVariable: 'BML_ILO_USERNAME', passwordVariable: 'BML_ILO_PASSWORD'),
                string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN')]) {
                timestamps {
                    sh './jenkins/scripts/bare_metal_lab/bml_test.sh clean'
                }
            }
        }
    }
}
