OSSO build of bpftrace
======================

This enables builds for bpftrace 0.17.1 for *Ubuntu/Jammy*. Also
includes *Netflix* *bpftop* (v0.4.0) in /usr/sbin.

-----------
xz missing?
-----------

If you notice that you don't have ``xz`` you can install ``xz-utils``::

    $ sudo /usr/bin/bpftrace -e 'BEGIN{exit()}'
    tar (child): xz: Cannot exec: No such file or directory
    tar (child): Error is not recoverable: exiting now
    tar: Child returned status 2
    tar: Error is not recoverable: exiting now
    Attaching 1 probe...

However, it appears that this might not be needed at all:

https://patchwork.kernel.org/project/linux-kbuild/patch/20200205154629.GA1257054@kroah.com/

So, to silence the error, you can:

- Install the right kernel headers (``linux-headers-$(uname -r)``).

- Install xz-utils, run it once and see that the files are cached here:
  ``/tmp/kheaders-5.15.0-92-generic/``

- Or do this workaround::

    mkdir /root/bpftrace-workaround/include/linux
    touch /root/bpftrace-workaround/include/linux/kconfig.h

    BPFTRACE_KERNEL_SOURCE=/root/bpftrace-workaround bpftrace -e 'BEGIN{exit()}'


------------
Docker build
------------

Just do::

    ./Dockerfile.build

And it will create the build files in ``Dockerfile.out/``.

For example::

    $ ls -1 Dockerfile.out/jammy/bpftrace_0.19.1-0osso0+ubu22.04
    bpftrace_0.19.1-0osso0+ubu22.04_amd64.buildinfo
    bpftrace_0.19.1-0osso0+ubu22.04_amd64.changes
    bpftrace_0.19.1-0osso0+ubu22.04_amd64.deb
    bpftrace_0.19.1-0osso0+ubu22.04.debian.tar.xz
    bpftrace_0.19.1-0osso0+ubu22.04.dsc
    bpftrace_0.19.1.orig.tar.gz
    bpftrace-dbgsym_0.19.1-0osso0+ubu22.04_amd64.ddeb


-------
EXAMPLE
-------

* On certain *Ubuntu/Jammy* machines, we have had occurrences where ZFS
  was stuck in a deadlock after load issues; probably in combination
  with K8S and containerd. The following script lists stuck processes,
  if there are any. In that case the process gets shown continuously
  instead of only once::

      #!/usr/bin/env bpftrace
      /*

      List runaway (containerd-shim) processes caused by a deadlock
      in zfsvfs_teardown.

      https://github.com/openzfs/zfs/blob/zfs-2.1.5/module/os/linux/zfs/zfs_vfsops.c#L1303-L1342

      Somewhere here, it's hanging. We can kill the process, but it will
      go into <defunct> zombie mode and keep eating cpu.

      Author: Walter Doekes
      Date: 2024-01-27

      Example output:

      > 22:31:12
      > @[containerd-shim, 3940927, taskq_wait_outstanding_check]: 2235168
      > @[containerd-shim, 3940927, taskq_wait_outstanding]: 2350712
      > 22:31:13
      > @[containerd-shim, 3940927, taskq_wait_outstanding_check]: 2432560
      > @[containerd-shim, 3940927, taskq_wait_outstanding]: 2432571

      ^- it doesn't go away? Deadlock.

      */
      kprobe:taskq_wait_outstanding_check
      {
              @[comm, pid, "taskq_wait_outstanding_check"] = count();
      }
      kprobe:taskq_wait_outstanding
      {
              @[comm, pid, "taskq_wait_outstanding"] = count();
      }
      kprobe:zfsvfs_teardown
      {
              @[comm, pid, "zfsvfs_teardown"] = count();
      }
      interval:s:1
      {
              time();
              print(@);
              clear(@);
      }
      END {
              clear(@);
      }
