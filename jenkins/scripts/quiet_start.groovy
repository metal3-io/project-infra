// $JENKINS_HOME/init.groovy.d/quiet-start.groovy

import jenkins.model.Jenkins
import hudson.security.ACL

/* see https://javadoc.jenkins-ci.org/jenkins/model/jenkins.html#doQuietDown(boolean,int,java.lang.String,boolean)

for automation, this should be blocking for several hours until it must go down and then timeout, proceeding
in "safe restart" mode - this will give time for jobs to complete and let pipelines resume later;
during startup as an init script it should instead engage immediately without blocking or restart,
holding off all jobs including paused pipelines until canceled separately, optionally on a timer */

boolean block = false               // Wait for jobs to complete and the build queue to become empty?
int timeout = 0                     // If blocking, timeout duration in milliseconds before releasing the block
String message = 'quiet startup'    // The message to display in the top banner
boolean safeRestart = false         // Pause and checkpoint pipeline jobs then restart afterwards?

int holdoff_minutes = 5             // How many minutes to hold off normal operation for after startup

def server = Jenkins.get()

// activate
server.doQuietDown(
    block as boolean,
    timeout as int,
    message as String,
    safeRestart as boolean
)

// release automatically on a timer
Thread.start {
    // wait
    Thread.sleep(holdoff_minutes * 60 * 1000)
    // canceling requires elevated privileges
    ACL.impersonate(ACL.SYSTEM)
    server.doCancelQuietDown()
}
