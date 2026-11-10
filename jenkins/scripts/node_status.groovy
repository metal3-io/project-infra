import jenkins.model.Jenkins
import hudson.model.Computer

// Retrieve all agent computers from the Jenkins instance
def computers = Jenkins.instance.computers

println("Checking status for ${computers.size()} agents:\n")
println(String.format('%-25s | %-10s | %-10s | %-10s', 'Agent Name', 'Status', 'Is Offline', 'Is Idle'))
println('-' * 65)

for (Computer computer : computers) {
    def nodeName = computer.name == '' ? 'Built-in Node (Controller)' : computer.name
    def isOffline = computer.isOffline()
    def isIdle = computer.isIdle()
    def status = isOffline ? 'OFFLINE' : 'ONLINE'
    println(String.format('%-25s | %-10s | %-10s | %-10s', nodeName, status, isOffline, isIdle))
    // Optional: Print reason if the agent is offline
    if (isOffline && computer.getOfflineCause() != null) {
        println("  └── Reason for Offline: ${computer.getOfflineCause().toString()}")
    }
}
