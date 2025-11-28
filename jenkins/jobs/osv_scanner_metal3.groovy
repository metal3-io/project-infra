// Jenkins pipeline: OSV-Scanner for three Metal3 repositories.

script {
    ci_git_branch = (env.PULL_PULL_SHA) ?: 'main'
    ci_git_base = (env.PULL_BASE_REF) ?: 'main'
    ci_git_url = 'https://github.com/metal3-io/project-infra.git'
    refspec = '+refs/heads/' + ci_git_base + ':refs/remotes/origin/' + ci_git_base + ' ' + ci_git_branch
}

def CAPM3_BRANCHES = []
def BMO_BRANCHES   = []
def IPAM_BRANCHES  = []
def IRSO_BRANCHES  = []

def CAPM3_TAGS = []
def BMO_TAGS   = []
def IPAM_TAGS  = []
def IRSO_TAGS  = []

def METAL3_GITHUB_BASE = 'https://github.com/metal3-io'
def METAL3_GOPROXY_BASE = 'https://proxy.golang.org/github.com/metal3-io'

def CAPM3_GOPROXY = "${METAL3_GOPROXY_BASE}/cluster-api-provider-metal3"
def BMO_GOPROXY   = "${METAL3_GOPROXY_BASE}/baremetal-operator"
def IPAM_GOPROXY  = "${METAL3_GOPROXY_BASE}/ip-address-manager"
def IRSO_GOPROXY  = "${METAL3_GOPROXY_BASE}/ironic-standalone-operator"

def CAPM3_GIT_URL = "${METAL3_GITHUB_BASE}/cluster-api-provider-metal3.git"
def BMO_GIT_URL   = "${METAL3_GITHUB_BASE}/baremetal-operator.git"
def IPAM_GIT_URL  = "${METAL3_GITHUB_BASE}/ip-address-manager.git"
def IRSO_GIT_URL  = "${METAL3_GITHUB_BASE}/ironic-standalone-operator.git"

def DEFAULT_SCAN_ARGS = '--recursive'
def GO_VERSION = ''
def OSV_SCANNER_COMMIT = '8b6727b2c439cdea8bc3a033bf7c76d76cbaee08'  // v2.2.4

def runOsvScan = { String repoName, String refType, String ref, String repoUrl, String goVersion, String failuresFile ->
    def workDir = "work-${repoName}-${refType}-${ref}".replace('/', '_')
    if (refType == 'branch') {
        sh "git clone --depth 1 --branch ${ref} ${repoUrl} ${workDir}"
    } else {
        sh "git clone ${repoUrl} ${workDir}"
    }
    dir(workDir) {
        if (refType == 'tag') {
            sh 'git fetch --tags --quiet || true'
            sh "git checkout ${ref}"
        }
        // Resolve go-version per repo if available, fallback to provided
        def gv = ''
        try { gv = sh(script: 'make go-version', returnStdout: true).trim() } catch (e) { echo "make go-version failed: ${e}" }
        if (!gv) { gv = goVersion }
        sh "echo 'GoVersionOverride = \"${gv}\"' > config.toml"

        def label   = "${repoName}-${refType}-${ref}".replace('/', '_')
        def outFile = "${WORKSPACE}/results/${repoName}_${refType}_${ref}.txt".replace('/', '_')
        sh """
          set +e
          bash -o pipefail -c "osv-scanner scan --config ./config.toml ${params.SCAN_ARGS} . | tee \\\"${outFile}\\\""
          ec=\$?
          if [ \$ec -ne 0 ]; then
            echo "${label}" >> ${WORKSPACE}/results/${failuresFile}
            exit \$ec
          fi
        """
    }
}

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

                    CAPM3_BRANCHES.add('main')
                    BMO_BRANCHES.add('main')
                    IPAM_BRANCHES.add('main')
                    IRSO_BRANCHES.add('main')

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

                    // exclude main branch from tag resolution
                    def capm3ReleaseBranches = CAPM3_BRANCHES.findAll { it != 'main' }
                    def bmoReleaseBranches = BMO_BRANCHES.findAll { it != 'main' }
                    def ipamReleaseBranches = IPAM_BRANCHES.findAll { it != 'main' }
                    def irsoReleaseBranches = IRSO_BRANCHES.findAll { it != 'main' }

                    CAPM3_TAGS = capm3ReleaseBranches.collect { br -> sh(script: "jenkins/scripts/get_latest_tag.sh ${CAPM3_GOPROXY}/@v/list ${br} 'beta|rc|alpha|pre'", returnStdout: true).trim()}.findAll { it }

                    BMO_TAGS = bmoReleaseBranches.collect { br -> sh(script: "jenkins/scripts/get_latest_tag.sh ${BMO_GOPROXY}/@v/list ${br} 'beta|rc|alpha|pre'", returnStdout: true).trim()}.findAll { it }

                    IPAM_TAGS = ipamReleaseBranches.collect { br -> sh(script: "jenkins/scripts/get_latest_tag.sh ${IPAM_GOPROXY}/@v/list ${br} 'beta|rc|alpha|pre'", returnStdout: true).trim()}.findAll { it }

                    IRSO_TAGS = irsoReleaseBranches.collect { br -> sh(script: "jenkins/scripts/get_latest_tag.sh ${IRSO_GOPROXY}/@v/list ${br} 'beta|rc|alpha|pre'", returnStdout: true).trim()}.findAll { it }

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
                                catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                                    runOsvScan(entry.name, 'branch', br, entry.url, GO_VERSION, 'branch_scan_failures.txt')
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
                                catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                                    runOsvScan(entry.name, 'tag', tg, entry.url, GO_VERSION, 'tag_scan_failures.txt')
                                }
                            }
                        }
                    }
                    parallel tasks
                }
            }
        }
        stage('Evaluate Scan Results') {
            steps {
                script {
                    if (fileExists('results/branch_scan_failures.txt')) {
                        echo 'One or more scans failed:'
                        sh 'cat results/branch_scan_failures.txt'
                        currentBuild.result = 'FAILURE'  // make whole build red
                    } else if (fileExists('results/tag_scan_failures.txt')) {
                        echo 'One or more scans failed:'
                        sh 'cat results/tag_scan_failures.txt'
                        currentBuild.result = 'UNSTABLE'  // make whole build yellow
                    } else {
                        echo 'All scans succeeded.'
                    }
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
