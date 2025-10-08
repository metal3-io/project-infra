# Diskimage Builder

As mentioned in the [documentation](https://docs.openstack.org/diskimage-builder/latest/index.html),
Diskimage Builder is a tool for automatically building customized operating
system images for use in clouds and other environments.

We utilize Diskimage Builder for building metal3-dev images.

## Elements

In Diskimage Builder (DIB), an "element" is a modular and reusable component
that defines a specific aspect of a disk image. Elements are like building
blocks used in the image creation process, allowing users to customize and
extend image functionality.

Each element handles a specific task, such as installing packages or modifying
files. Users choose which elements to include, offering flexibility. When
creating a custom image with Diskimage Builder, users select elements, and
these are combined to form the final disk image. Examples of elements include
"base," "apache," or "cloud-init," each focusing on a specific part of the
image's configuration.

## Custom Elements

For metal3-dev image building purposes, we create three custom elements:
ci-base, ubuntu-ci, and centos-ci elements. The ci-base element is for
installing common packages and configurations for both Ubuntu and CentOS. The
ubuntu-ci and centos-ci elements are for installing packages and configuring
the respective operating system images. More information on developing custom
elements can be found [here](https://docs.openstack.org/diskimage-builder/latest/developer/developing_elements.html).

## Building an Image with Diskimage Builder

We use the following command to build an image:

```bash
disk-image-create --no-tmpfs -a amd64 ubuntu-ci ubuntu -o "${CI_IMG_NAME}"
block-device-efi
```

* **--no-tmpfs**: This flag specifies that the temporary file system (tmpfs)
should not be used during the image creation process. Tmpfs is a file system
that resides in memory, and using this flag indicates that temporary files
should be written directly to disk instead of in-memory.

* **-a amd64***: This option specifies the architecture of the image. In this
case, it is set to amd64, indicating a 64-bit x86 architecture.

* **ubuntu-ci**, **ubuntu**: These are the elements or components used in
building the image. The image is based on the "ubuntu-ci" element, a
development environment for Ubuntu. Additionally, the "ubuntu" element is
specified, likely including the base configuration for an Ubuntu-based image.

* **-o** **"${CI_IMG_NAME}"**: This option specifies the output file or
image name. The value is provided through the variable ${CI_IMG_NAME}.

* **block-device-efi**: This is an additional element specified for image
creation. It likely includes configurations or tasks related to block devices
and EFI (Extensible Firmware Interface), commonly used in modern systems for booting.

More information on building and image via Diskimage Builder can be found [here](https://docs.openstack.org/diskimage-builder/latest/user_guide/building_an_image.html).

## Debugging

In some cases, it might be useful to create an image with a pre-configured user
account for debugging purposes. This can be achieved by adding the `devuser`
element. See the
[documentation](https://docs.openstack.org/diskimage-builder/latest/elements/devuser/README.html)
for more information.

Example:

Add `devuser` to the list of elements in the `element-deps` file. Then set the
following environment variables to configure the user account:

```bash
export DIB_DEV_USER_USERNAME="developer"
export DIB_DEV_USER_PWDLESS_SUDO="yes"
export DIB_DEV_USER_AUTHORIZED_KEYS="/path/to/authorized_keys"
```
