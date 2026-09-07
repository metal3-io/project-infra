// Global variables
def TIMEOUT = 600, ci_git_url, ci_git_branch, refspec
def CURRENT_START_TIME, CURRENT_END_TIME, GRAFANA_VIEW
def LOG_URL = 'https://log.apps.staging.metal3.io/view/?orgId=1&timezone=browser&kiosk'

script {
    ci_git_url   = 'https://github.com/metal3-io/project-infra.git'
    ci_git_branch = 'main'
    refspec = '+refs/heads/*:refs/remotes/origin/*'
}

def START_TIME = currentBuild.getStartTimeInMillis()
GRAFANA_VIEW = """${LOG_URL}&from=${START_TIME}&to=now&var-pipeline=${env.JOB_NAME}&var-build=${BUILD_NUMBER}"""
currentBuild.description = """<a href='${GRAFANA_VIEW}'>View in log collector</a>"""

pipeline {
    agent { label 'metal3ci-8c32gb-ubuntu-oci' }
    stages {
        stage('SCM') {
            options {
                timeout(time: 5, unit: 'MINUTES')
            }
            steps {
                /* Checkout CI Repo */
                deleteDir()
                checkout([$class: 'GitSCM',
                 branches: [[name: ci_git_branch]],
                 doGenerateSubmoduleConfigurations: false,
                 userRemoteConfigs: [[url: ci_git_url,  refspec: refspec, credentialsId: 'metal3-clusterctl-github-token']]])
            }
        }
        stage('Clean old integration test vms') {
            options {
                timeout(time: TIMEOUT, unit: 'SECONDS')
            }
            steps {
                script {
                    withCredentials([
                file(credentialsId: 'metal3-oracle-cloud-api-private-key', variable: 'OCI_KEY_FILE'),
                file(credentialsId: 'metal3-oracle-paris-env-vars', variable: 'OCI_CLI_ENV_FILE'),
                ])  {
                        timestamps {
                            sh '''
                            set -a +x
                            . "$OCI_CLI_ENV_FILE"
                            set +a -x
                            ./jenkins/scripts/clean_resources.sh
                            '''
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
