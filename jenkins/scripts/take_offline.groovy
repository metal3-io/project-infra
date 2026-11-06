import jenkins.model.Jenkins
import hudson.model.Computer
import hudson.slaves.OfflineCause

// Customize your maintenance message here
def maintenanceReason = 'Global maintenance window - taking all nodes offline safely.'
def cause = new OfflineCause.UserCause(hudson.model.User.current(), maintenanceReason)

def computers = Jenkins.instance.computers
println("Processing ${computers.size()} nodes...\n")

for (Computer computer : computers) {
    // Skip the built-in controller node so Jenkins administrative functions stay active
    if (computer.name == '') {
        println('Skipping: Built-in Node (Controller)')
        continue
    }
    def agentName = computer.name
    if (!computer.isTemporarilyOffline()) {
        computer.setTemporarilyOffline(true, cause)
        println("Success: [${agentName}] is now marked TEMPORARILY OFFLINE.")
    } else {
        println("Skipped: [${agentName}] was already temporarily offline.")
    }
}
