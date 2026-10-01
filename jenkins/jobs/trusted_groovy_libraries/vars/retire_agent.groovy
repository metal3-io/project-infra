import jenkins.model.Jenkins
import hudson.slaves.AbstractCloudComputer
// This file is intended to be used as a "Trusted Groovy Pipeline Library"
// and automatically made available for all Jenkins Pipeline jobs.
// TO USE this function, add retire_agent() to any pipeline step (outside
// the script block)

// This function is used to decommission nodes manually.
// OCI cloud plugin does not decommission the dynamically generated jenkins
// agents (nodes). Dynamic nodes that linger might get picked up by a second
// job, but then the cloud plugin deletes the node and breaks the second job.
// The goal is to decommission the node before a second job could pick it up
// to avoid breaking the second job.
def call() {
    def nodeName = env.NODE_NAME
    if (!nodeName || nodeName == 'built-in') {
        return
    }
    def computer = Jenkins.get().getComputer(nodeName)
    // Only affect cloud agents accessed via the cloud plugin
    // instanceof here just filters by node type, not a polymorphic design
    if (computer instanceof AbstractCloudComputer) { // groovylint-disable-line Instanceof
        echo "Preventing reuse of ${nodeName} to allow idle recycling..."
        computer.setAcceptingTasks(false)
    }
}
