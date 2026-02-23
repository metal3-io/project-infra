// Global variables
def TIMEOUT = 600, ci_git_url, ci_git_branch, refspec

script {
    ci_git_url   = 'https://github.com/metal3-io/project-infra.git'
    ci_git_branch = 'main'
    refspec = '+refs/heads/*:refs/remotes/origin/*'
}

pipeline {
    agent { label 'metal3ci-4c16gb-ubuntu-jnlp' }
    environment {
        OS_USERNAME = 'metal3ci'
        OS_AUTH_URL = 'https://kna1.citycloud.com:5000'
        OS_USER_DOMAIN_NAME = 'CCP_Domain_37137'
        OS_PROJECT_DOMAIN_NAME = 'CCP_Domain_37137'
        OS_REGION_NAME = 'Kna1'
        OS_PROJECT_NAME = 'Default Project 37137'
        OS_TENANT_NAME = 'Default Project 37137'
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
                checkout([$class: 'GitSCM',
                 branches: [[name: ci_git_branch]],
                 doGenerateSubmoduleConfigurations: false,
                 extensions: [[$class: 'WipeWorkspace'],
                 [$class: 'CleanCheckout'],
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
}
