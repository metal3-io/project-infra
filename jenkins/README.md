# Nordix Jenkins CI

Some integration tests are running in the [Nordix](https://www.nordix.org)
infrastructure. Nordix provides a
[Jenkins](https://jenkins.nordix.org/view/Airship/) instance and cloud resources
on [CityCloud](https://www.citycloud.com/) for the Airship project. We use those
resources to run integration tests for Metal3.

## nordixinfra bot

In Github the Jenkins bot uses *metal3-jenkins* username. It will post comments
on Pull Requests in the metal3-dev-env, baremetal-operator and
cluster-api-provider-metal3 repositories.

### Admins whitelist

All members of the metal3-io organization that set their membership to be
publicly visible will get admin rights on the CI jobs. This means :

 * They can start the jobs on their PR directly
 * They can start the jobs for PR of authors that are not in the organization
 * They can add authors to whitelist so that the authors can start jobs on any
   further PR on their own, by commenting **add to whitelist** on the PR

### Commands

We have multiple jobs that run some integration tests. The jobs can be
triggered on PR from metal3-dev-env, baremetal-operator and
cluster-api-provider-metal3 repositories by commenting the commands below.
The job result will be posted as a comment.

 * **/test-v1a2-integration** run integration tests for V1alpha2 on Ubuntu
 * **/test-v1a2-centos-integration** run integration tests for V1alpha2 on
   CentOS
 * **/test-v1a3-integration** run integration tests for V1alpha3 on Ubuntu
 * **/test-v1a3-centos-integration** run integration tests for V1alpha3 on
   CentOS   
 * **/test-integration** run integration tests for V1alpha4 on Ubuntu
 * **/test-centos-integration** run integration tests for V1alpha4 on
   CentOS

It is also possible to prevent any job run by adding **/skip-test** in the PR
description.

If the author is not in the whitelist but should be trusted then by adding a
comment **add to whitelist** on the PR, the author will then be able to run the
jobs on its own.

### Cloud Resources cleanup

There is a Jenkins [master job](https://jenkins.nordix.org/view/Airship/job/airship_master_integration_tests_cleanup/)
that every 6 hours cleans up all the leftover VMs from
[CityCloud](https://www.citycloud.com/) which fail to be deleted at the end of
v1alphaX integration test.

### "Can one of the admins verify this patch?"

For all the PRs from authors that are not whitelisted, the bot will add a
comment "*Can one of the admins verify this patch?*". This means that the author
is not in the whitelist and that someone from the metal3-io organization should
review the PR
and run the tests (with */test-integration*) or add the author to whitelist if
trusted.

## Jenkins configuration

The jenkins configuration is stored in two places. The Nordix gerrit instance
contains the jenkins job configuration and the Github airship-dev-tools
repository contains the jobs pipeline.

### job configuration

The job configuration is stored here. Please
announce if some reviews are needed on #cluster-api-baremetal in Kubernetes
slack or send an email to estjorvas [at] est.tech mailing list.

### job pipeline

The pipeline for the jobs is in the `jobs` folder. The scripts running
the tests are in the `scripts` folder.

## Job image

We use pre-baked images to run the tests. The images are based on Ubuntu or
CentOS.

The image building scripts can be found here for [Ubuntu](https://github.com/Nordix/airship-dev-tools/blob/master/ci/images/gen_metal3_ubuntu_image.sh).

## Contact

In case of issues or question on the Jenkins CI, please contact the maintainers
by email to estjorvas [at] est.tech or by posting your message on the
\#cluster-api-baremetal channel on Kubernetes Slack.
