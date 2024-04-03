OSSO build of bpftrace
======================

This enables builds for bpftrace 0.17.1 for *Ubuntu/Jammy*.


------------
Docker build
------------

Just do::

    ./Dockerfile.build

And it will create the build files in ``Dockerfile.out/``.

For example::

    $ ls -1 Dockerfile.out/jammy/bpftrace_0.17.1-0osso0+ubu22.04/
    bpftrace_0.17.1-0osso0+ubu22.04_amd64.buildinfo
    bpftrace_0.17.1-0osso0+ubu22.04_amd64.changes
    bpftrace_0.17.1-0osso0+ubu22.04_amd64.deb
    bpftrace_0.17.1-0osso0+ubu22.04.debian.tar.xz
    bpftrace_0.17.1-0osso0+ubu22.04.dsc
    bpftrace_0.17.1.orig.tar.gz


----
TODO
----

* Include bpftop in the release:
  https://github.com/Netflix/bpftop/releases

* ``dpkg-shlibdeps: warning: package could avoid a useless dependency if
  debian/bpftrace/usr/bin/bpftrace was not linked against libz.so.1 (it
  uses none of the library's symbols)``

* Try newer builds than 0.17.1.


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


