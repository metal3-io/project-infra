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
    agent { label 'metal3ci-4c16gb-ubuntu-jnlp' }
    environment {
        OS_USERNAME = 'metal3ci'
        OS_AUTH_URL = 'https://xerces.ericsson.net:5000'
        OS_PROJECT_ID = 'b62dc8622f87407589de9f7dcec13d25'
        OS_INTERFACE = 'public'
        OS_PROJECT_NAME = 'EST_Metal3_CI'
        OS_USER_DOMAIN_NAME = 'xerces'
        OS_AUTH_VERSION = 3
        OS_IDENTITY_API_VERSION = 3
    }
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
                 extensions: [[$class: 'CleanCheckout'],
                 [$class: 'CleanBeforeCheckout']],
                 submoduleCfg: [],
                 userRemoteConfigs: [[url: ci_git_url,  refspec: refspec]]])
            }
        }
        stage('Clean old integration test vms') {
            options {
                timeout(time: TIMEOUT, unit: 'SECONDS')
            }
            steps {
                script {
                    withCredentials([
                usernamePassword(credentialsId: 'xerces-est-metal3ci', usernameVariable: 'OPENSTACK_USERNAME_XERCES', passwordVariable: 'OPENSTACK_PASSWORD_XERCES'),
                ])  {
                        timestamps {
                            sh './jenkins/scripts/clean_resources.sh'
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
