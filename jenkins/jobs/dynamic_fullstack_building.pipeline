import java.text.SimpleDateFormat

// 3 hours
def TIMEOUT = 10800

script {

  UPDATED_REPO = "https://github.com/${env.REPO_OWNER}/${env.REPO_NAME}.git"
  echo "Test triggered from ${UPDATED_REPO}"
  ci_git_url = "https://github.com/metal3-io/project-infra.git"

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
  agent { label 'metal3ci-8c32gb-ubuntu' }
  environment {
    // supplied by prow
    REPO_ORG = "${env.REPO_OWNER}"
    REPO_NAME = "${env.REPO_NAME}"
    REPO_BRANCH = "${env.PULL_BASE_REF}"
    UPDATED_BRANCH = "${env.PULL_PULL_SHA}"
    PR_ID = "${env.PULL_NUMBER}"
    // pipeline script local
    UPDATED_REPO = "${UPDATED_REPO}"
    METAL3_CI_USER="metal3ci"
    RT_URL="https://artifactory.nordix.org/artifactory"
    CURRENT_DIR = sh (
                      script: 'readlink -f "."',
                      returnStdout: true
                     ).trim()
    // jenkins job auto generates
    BUILD_TAG = "${env.BUILD_TAG}"
  }
  stages {
    stage('Building and testing full Metal3 stack'){
      options {
        timeout(time: TIMEOUT, unit: 'SECONDS')
      }
      steps {
        script {
          CURRENT_START_TIME = System.currentTimeMillis()
        }
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
        /* Pass all the credentials */
        withCredentials([usernamePassword(credentialsId: 'infra-nordix-artifactory-api-key', usernameVariable: 'RT_USER', passwordVariable: 'RT_TOKEN')]) {
          withCredentials([usernamePassword(credentialsId: 'metal3ci_harbor', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASSWORD')])  {
            withCredentials([string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN')]) {
              /* Fullstack building script */
              ansiColor('xterm') {
                timestamps {
                  sh './jenkins/scripts/dynamic_worker_workflow/fullstack.sh'
                }
              }
            }
          }
        }
      }
    }
  }
  post{
    always{
      script {
        CURRENT_END_TIME = System.currentTimeMillis()
        if ((((CURRENT_END_TIME - CURRENT_START_TIME)/1000) - TIMEOUT) > 0) {
          echo "Failed due to timeout"
          currentBuild.result = 'FAILURE'
        }
      }
      timestamps {
        /* Collect the logs */
        sh './jenkins/scripts/dynamic_worker_workflow/fetch_logs.sh'
        archiveArtifacts "logs-${env.BUILD_TAG}.tgz"
      }
    }
  }
}
