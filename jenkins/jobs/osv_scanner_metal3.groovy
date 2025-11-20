// Jenkins pipeline: OSV-Scanner for three Metal3 repositories.

script {
    ci_git_branch = (env.PULL_PULL_SHA) ?: 'main'
    ci_git_base = (env.PULL_BASE_REF) ?: 'main'
    ci_git_url = 'https://github.com/metal3-io/project-infra.git'
    refspec = '+refs/heads/' + ci_git_base + ':refs/remotes/origin/' + ci_git_base + ' ' + ci_git_branch
}

array CAPM3_BRANCHES = []
array BMO_BRANCHES   = []
array IPAM_BRANCHES  = []
array IRSO_BRANCHES  = []

array CAPM3_TAGS = []
array BMO_TAGS   = []
array IPAM_TAGS  = []
array IRSO_TAGS  = []

string METAL3_GITHUB_BASE = 'https://github.com/metal3-io/'
string METAL3_GOPROXY_BASE = 'https://proxy.golang.org/github.com/metal3-io/'

string CAPM3_GOPROXY = "${METAL3_GOPROXY_BASE}cluster-api-provider-metal3"
string BMO_GOPROXY   = "${METAL3_GOPROXY_BASE}baremetal-operator"
string IPAM_GOPROXY  = "${METAL3_GOPROXY_BASE}ip-address-manager"
string IRSO_GOPROXY  = "${METAL3_GOPROXY_BASE}ironic-standalone-operator"

string CAPM3_GIT_URL = "${METAL3_GITHUB_BASE}cluster-api-provider-metal3.git"
string BMO_GIT_URL   = "${METAL3_GITHUB_BASE}baremetal-operator.git"
string IPAM_GIT_URL  = "${METAL3_GITHUB_BASE}ip-address-manager.git"
string IRSO_GIT_URL  = "${METAL3_GITHUB_BASE}ironic-standalone-operator.git"

string DEFAULT_SCAN_ARGS = '--recursive'
string GO_VERSION = ''
string OSV_SCANNER_COMMIT = '8b6727b2c439cdea8bc3a033bf7c76d76cbaee08'  // v2.2.4

script { agent_label = 'metal3ci-8c32gb-ubuntu' }

pipeline {
    agent { label agent_label }
    options { timestamps() }
    parameters {
        string(
      name: 'SCAN_ARGS',
      defaultValue: DEFAULT_SCAN_ARGS,
      description: 'Extra OSV-Scanner arguments'
    )
    }
    stages {
        stage('Checkout CI Repo') {
            options {
                timeout(time: 50, unit: 'MINUTES')
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
        stage('Resolve Branches') {
            steps {
                script {
                    sh 'chmod +x jenkins/scripts/get_last_n_release_branches.sh || true'
                    CAPM3_BRANCHES = sh(
                      script: "jenkins/scripts/get_last_n_release_branches.sh ${CAPM3_GIT_URL} 2",
                      returnStdout: true
                    ).trim().split('\\n').findAll { it }
                    BMO_BRANCHES = sh(
                      script: "jenkins/scripts/get_last_n_release_branches.sh ${BMO_GIT_URL} 2",
                      returnStdout: true
                    ).trim().split('\\n').findAll { it }
                    IPAM_BRANCHES = sh(
                      script: "jenkins/scripts/get_last_n_release_branches.sh ${IPAM_GIT_URL} 2",
                      returnStdout: true
                    ).trim().split('\\n').findAll { it }
                    IRSO_BRANCHES = sh(
                      script: "jenkins/scripts/get_last_n_release_branches.sh ${IRSO_GIT_URL} 3",
                      returnStdout: true
                    ).trim().split('\\n').findAll { it }

                    echo "CAPM3_BRANCHES=${CAPM3_BRANCHES}"
                    echo "BMO_BRANCHES=${BMO_BRANCHES}"
                    echo "IPAM_BRANCHES=${IPAM_BRANCHES}"
                    echo "IRSO_BRANCHES=${IRSO_BRANCHES}"

                    if (!CAPM3_BRANCHES || !BMO_BRANCHES || !IPAM_BRANCHES || !IRSO_BRANCHES) {
                        error 'Failed to resolve one or more branch sets.'
                    }
                }
            }
        }
        stage('Resolve Tags') {
            steps {
                script {
                    sh 'chmod +x jenkins/scripts/get_latest_tag.sh || true'
                    CAPM3_TAGS = CAPM3_BRANCHES.collect { br -> sh(script: "jenkins/scripts/get_latest_tag.sh ${CAPM3_GOPROXY}/@v/list ${br} 'beta|rc|alpha|pre'", returnStdout: true).trim()}.findAll { it }

                    BMO_TAGS = BMO_BRANCHES.collect { br -> sh(script: "jenkins/scripts/get_latest_tag.sh ${BMO_GOPROXY}/@v/list ${br} 'beta|rc|alpha|pre'", returnStdout: true).trim()}.findAll { it }

                    IPAM_TAGS = IPAM_BRANCHES.collect { br -> sh(script: "jenkins/scripts/get_latest_tag.sh ${IPAM_GOPROXY}/@v/list ${br} 'beta|rc|alpha|pre'", returnStdout: true).trim()}.findAll { it }

                    IRSO_TAGS = IRSO_BRANCHES.collect { br -> sh(script: "jenkins/scripts/get_latest_tag.sh ${IRSO_GOPROXY}/@v/list ${br} 'beta|rc|alpha|pre'", returnStdout: true).trim()}.findAll { it }

                    echo "CAPM3_TAGS=${CAPM3_TAGS}"
                    echo "BMO_TAGS=${BMO_TAGS}"
                    echo "IPAM_TAGS=${IPAM_TAGS}"
                    echo "IRSO_TAGS=${IRSO_TAGS}"

                    if (!CAPM3_TAGS || !BMO_TAGS || !IPAM_TAGS || !IRSO_TAGS) {
                        error 'Failed to resolve one or more tag sets.'
                    }
                }
            }
        }
        stage('Init Repo Map') {
            steps {
                script {
                    REPO_BRANCH_MAP = [
                      [
                        name    : 'CAPM3',
                        url     : CAPM3_GIT_URL,
                        branches: CAPM3_BRANCHES,
                        tags    : CAPM3_TAGS
                      ],
                      [
                        name    : 'BMO',
                        url     : BMO_GIT_URL,
                        branches: BMO_BRANCHES,
                        tags    : BMO_TAGS
                      ],
                      [
                        name    : 'IPAM',
                        url     : IPAM_GIT_URL,
                        branches: IPAM_BRANCHES,
                        tags    : IPAM_TAGS
                      ],
                      [
                        name    : 'IRSO',
                        url     : IRSO_GIT_URL,
                        branches: IRSO_BRANCHES,
                        tags    : IRSO_TAGS
                      ]
                    ]
                    echo "Initialized repo list; total repos: ${REPO_BRANCH_MAP.size()}"
                }
            }
        }
        stage('Resolve Go Version') {
            steps {
                script {
                    echo 'Resolving Go version from cluster-api-provider-metal3 (make go-version)'
                    sh "rm -rf gover-capm3 && git clone --depth 1 ${CAPM3_GIT_URL} gover-capm3"
                    def raw = sh(script: 'cd gover-capm3 && make go-version', returnStdout: true).trim()
                    if (!raw) {
                        error 'make go-version returned empty'
                    }
                    GO_VERSION = raw
                    echo "Resolved GO_VERSION=${GO_VERSION}"
                }
            }
        }
        stage('Install OSV-Scanner') {
            environment {
                PATH   = "/usr/local/go/bin:${env.PATH}"
                GOROOT = '/usr/local/go'
                GOPATH = "${env.WORKSPACE}/go"
            }
            steps {
                script {
                    echo "Running install scripts for Go ${GO_VERSION} and OSV-Scanner"
                    sh """
                      curl -sSfL https://go.dev/dl/"go${GO_VERSION}".linux-amd64.tar.gz -o go.tar.gz
                      sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go.tar.gz
                      rm go.tar.gz
                      export PATH=\$PATH:/usr/local/go/bin
                      go install github.com/google/osv-scanner/v2/cmd/osv-scanner@${OSV_SCANNER_COMMIT}
                    """
                }
                sh 'mkdir -p results'
            }
        }
        stage('Scan Metal3 Repo branches') {
            environment {
                PATH   = "/usr/local/go/bin:${env.WORKSPACE}/go/bin:${env.PATH}"
                GOROOT = '/usr/local/go'
                GOPATH = "${env.WORKSPACE}/go"
            }
            steps {
                script {
                    sh 'mkdir -p results'
                    def tasks = [:]

                    REPO_BRANCH_MAP.each { entry ->
                        // Branch scans
                        entry.branches.each { br ->
                            def label = "${entry.name}-branch-${br}"
                            tasks[label] = {
                                def workDir = "work-${entry.name}-branch-${br}"
                                sh "git clone --depth 1 --branch ${br} ${entry.url} ${workDir}"
                                dir(workDir) {
                                    def go_version = ''
                                    try {
                                        go_version = sh(script: 'make go-version', returnStdout: true).trim()
                                } catch (err) {
                                        echo "make go-version failed: ${err}"
                                    }
                                    if (!go_version) {
                                        go_version = GO_VERSION
                                    }
                                    sh "echo 'GoVersionOverride = \"${go_version}\"' > config.toml"
                                    def outFile = "${WORKSPACE}/results/${entry.name}_branch_${br}.txt"
                                    sh "osv-scanner scan --config ./config.toml ${params.SCAN_ARGS} --output ${outFile} ."
                                }
                            }
                        }
                    }
                    parallel tasks
                }
            }
        }
        stage('Scan Metal3 Repo tags') {
            environment {
                PATH   = "/usr/local/go/bin:${env.WORKSPACE}/go/bin:${env.PATH}"
                GOROOT = '/usr/local/go'
                GOPATH = "${env.WORKSPACE}/go"
            }
            steps {
                script {
                    sh 'mkdir -p results'
                    def tasks = [:]

                    REPO_BRANCH_MAP.each { entry ->
                        // Tag scans
                        entry.tags.each { tg ->
                            def label = "${entry.name}-tag-${tg}".replace('/', '_')
                            tasks[label] = {
                                def workDir = "work-${entry.name}-tag-${tg}"
                                sh "git clone ${entry.url} ${workDir}"
                                dir(workDir) {
                                    sh 'git fetch --tags --quiet || true'
                                    sh "git checkout ${tg}"
                                    def go_version = ''
                                    try {
                                        go_version = sh(script: 'make go-version', returnStdout: true).trim()
                                } catch (err) {
                                        echo "make go-version failed: ${err}"
                                    }
                                    if (!go_version) {
                                        go_version = GO_VERSION
                                    }
                                    sh "echo 'GoVersionOverride = \"${go_version}\"' > config.toml"
                                    def outFile = "${WORKSPACE}/results/${entry.name}_tag_${tg}.txt"
                                    sh "osv-scanner scan --config ./config.toml ${params.SCAN_ARGS} --output ${outFile} ."
                                }
                            }
                        }
                    }
                    parallel tasks
                }
            }
        }
    }
    post {
        always {
            script {
                archiveArtifacts artifacts: 'results/*.txt', allowEmptyArchive: true
            }
        }
    }
}

