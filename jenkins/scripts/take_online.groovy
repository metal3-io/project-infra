import jenkins.model.Jenkins
import hudson.model.Computer

def computers = Jenkins.instance.computers
println("Processing ${computers.size()} nodes to bring them back online...\n")

for (Computer computer : computers) {
    if (computer.name == '') {
        continue // Skip controller
    }
    def agentName = computer.name
    if (computer.isTemporarilyOffline()) {
        computer.setTemporarilyOffline(false, null)
        println("Success: [${agentName}] is now BACK ONLINE.")
    } else {
        println("Skipped: [${agentName}] is already online.")
    }
}
