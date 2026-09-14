// Global variables
def ci_git_url, ci_git_branch, ci_git_base, refspec
def CURRENT_END_TIME, GRAFANA_VIEW
def LOG_URL = 'https://log.apps.test.metal3.io/view/?orgId=1&timezone=browser&kiosk'

script {
    ci_git_url   = 'https://github.com/metal3-io/project-infra.git'
    ci_git_branch = (env.PULL_PULL_SHA) ?: 'main'
    ci_git_base = (env.PULL_BASE_REF) ?: 'main'
    refspec = '+refs/heads/' + ci_git_base + ':refs/remotes/origin/' + ci_git_base + ' ' + ci_git_branch
}

def START_TIME = currentBuild.getStartTimeInMillis()
GRAFANA_VIEW = """${LOG_URL}&from=${START_TIME}&to=now&var-pipeline=${env.JOB_NAME}&var-build=${BUILD_NUMBER}"""
currentBuild.description = """<a href='${GRAFANA_VIEW}'>View in log collector</a>"""

pipeline {
    options {
        // We verify the CI images by uploading and testing them as jenkins agents.
        // If multiple jobs would run in parallel, they may overwrite each others image
        // and/or delete them before the test is finished.
        disableConcurrentBuilds()
    }
    agent none
    environment {
        IMAGE_TYPE = "${env.IMAGE_TYPE}"
        METAL3_CI_USER = 'metal3ci'
        KUBERNETES_VERSION = "${env.KUBERNETES_VERSION}"
        CRICTL_VERSION = "${env.CRICTL_VERSION}"
        CRIO_VERSION = "${env.CRIO_VERSION}"
        RT_URL = 'https://artifactory.nordix.org/artifactory'
        CAPM3RELEASEBRANCH = "${env.capm3_release_branch}"
        BMORELEASEBRANCH = "${env.bmo_release_branch}"
        CAPI_VERSION = "${env.CAPI_VERSION}"
        CAPM3_VERSION = "${env.CAPM3_VERSION}"
    }
    stages {
        stage('SCM') {
            matrix {
                agent { label 'metal3ci-8c32gb-ubuntu-oci' }
                options { ansiColor('xterm') }
                axes {
                    axis {
                        name 'IMAGE_OS'
                        values 'ubuntu', 'centos', 'leap'
                    }
                }
                environment {
                    IMAGE_OS = "${IMAGE_OS}"
                }
                stages {
                    stage('Checkout CI Repo') {
                        options {
                            timeout(time: 5, unit: 'MINUTES')
                        }
                        steps {
                            deleteDir()
                            checkout([
                $class: 'GitSCM',
                branches: [[name: ci_git_branch]],
                doGenerateSubmoduleConfigurations: false,
                userRemoteConfigs: [[url: ci_git_url, refspec: refspec, credentialsId: 'metal3-clusterctl-github-token']]
              ])
                        }
                    }
                    stage('Build disk image') {
                        options {
                            timeout(time: 1, unit: 'HOURS')
                        }
                        steps {
                            echo "Building ${IMAGE_OS} ${IMAGE_TYPE} image"
                            script {
                                sh './jenkins/image_building/build-image.sh'
                            }
                        }
                    }
                    stage('Upload the new CI Image to OCI candidate') {
                        options {
                            timeout(time: 30, unit: 'MINUTES')
                        }
                        when {
                            expression { env.IMAGE_TYPE == 'ci' }
                        }
                        steps {
                            withCredentials([
                  file(credentialsId: 'metal3-oracle-cloud-api-private-key', variable: 'OCI_KEY_FILE'),
                  file(credentialsId: 'metal3-oracle-paris-env-vars', variable: 'OCI_CLI_ENV_FILE')
                            ]) {
                                sh '''
                                set -a +x
                                . "$OCI_CLI_ENV_FILE"
                                set +a -x
                                ./jenkins/image_building/upload-ci-image-oci.sh upload-candidate "$(cat image_name.txt)"
                                '''
                            }
                        }
                    }
                    stage('Verify the new node image') {
                        options {
                            timeout(time: 3, unit: 'HOURS')
                        }
                        when {
                            expression { env.IMAGE_TYPE == 'node' }
                        }
                        steps {
                            echo "Testing new ${IMAGE_OS} node image"
                            withCredentials([string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN')]) {
                                script {
                                    def imageName = readFile('image_name.txt').trim()

                                    sh """
                                    echo "Testing ${imageName}"
                                    ./jenkins/image_building/verify-node-image.sh ${imageName}
                                    """
                                }
                            }
                        }
                    }
                    stage('Verify the new CI image') {
                        agent { label "metal3ci-${IMAGE_OS}-staging" }
                        options {
                            timeout(time: 2, unit: 'HOURS')
                        }
                        when {
                            // IMPORTANT: We must evaluate the when block before the agent or we will get stuck
                            // since there is no stagig image available when IMAGE_TYPE is not "ci".
                            beforeAgent true
                            expression { env.IMAGE_TYPE == 'ci' }
                        }
                        steps {
                            echo "Testing new ${IMAGE_OS} CI image"
                            withCredentials([string(credentialsId: 'metal3-clusterctl-github-token', variable: 'GITHUB_TOKEN')]) {
                                script {
                                    sh './jenkins/image_building/verify-ci-image.sh'
                                }
                            }
                        }
                    }
                    stage('Upload the new Image') {
                        options {
                            timeout(time: 30, unit: 'MINUTES')
                        }
                        when {
                            // Don't upload from PR tests
                            expression { ci_git_branch == 'main' }
                            expression { env.IMAGE_TYPE == 'node' }
                        }
                        steps {
                            withCredentials([
                              usernamePassword(credentialsId: 'infra-nordix-artifactory-api-key', usernameVariable: 'RT_USER', passwordVariable: 'RT_TOKEN')
                              ]) {
                                script {
                                    def imageName = readFile('image_name.txt').trim()
                                    echo "Uploading ${imageName}"

                                    sh """
                                    ./jenkins/image_building/upload-node-image.sh ${imageName}
                                    """
                                }
                            }
                        }
                    }
                    stage('Promote OCI candidate to latest') {
                        options {
                            timeout(time: 30, unit: 'MINUTES')
                        }
                        when {
                            // Don't upload from PR tests
                            expression { ci_git_branch == 'main' }
                            beforeAgent true
                            expression { env.IMAGE_TYPE == 'ci' }
                        }
                        steps {
                            withCredentials([
                              file(credentialsId: 'metal3-oracle-cloud-api-private-key', variable: 'OCI_KEY_FILE'),
                              file(credentialsId: 'metal3-oracle-paris-env-vars', variable: 'OCI_CLI_ENV_FILE'),
                              ]) {
                                echo 'Promoting OCI candidate image to latest'
                                sh '''
                                set -a +x
                                . "$OCI_CLI_ENV_FILE"
                                set +a -x
                                ./jenkins/image_building/upload-ci-image-oci.sh promote-candidate
                                '''
                            }
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
                GRAFANA_VIEW = """${LOG_URL}&from=${START_TIME}&to=${CURRENT_END_TIME}&var-pipeline=${env.JOB_NAME}&var-build=${BUILD_NUMBER}"""
                currentBuild.description = """<a href='${GRAFANA_VIEW}'>View in log collector</a>"""
            }
        }
    }
}
