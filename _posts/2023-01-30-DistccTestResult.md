---
title: Distcc Test Result (AutoUpdate with CI Build)
articles:
   excerpt_type: html
---

<!--more-->
# Hardware Environment

S905X3 CPU x 4 < — distcc node

RK3399 CPU x 1 < — distcc node

RK3588 CPU x 1 < — main machine use to build

i5-7200U CPU x1 < — distcc node

# Test Result

## Build Node

Build Host : aarch64

Build Target : aarch64

Build Date : Sun Jan 29 19:53:27 UTC 2023

`commit ac66a99cf18a8046cf580f350b4e09cde8cd18e3`

Configure Flag :

`./configure --prefix=/opt/node_bin_git`

Provided Compiler :

```bash
ihexon@5b /m/z/node (main)> gcc -v
Using built-in specs.
COLLECT_GCC=aarch64-linux-gnu-gcc
COLLECT_LTO_WRAPPER=/usr/lib/gcc/aarch64-linux-gnu/10/lto-wrapper
Target: aarch64-linux-gnu
Configured with: ../src/configure -v --with-pkgversion='Debian 10.2.1-6' --with-bugurl=file:///usr/share/doc/gcc-10/README.Bugs --enable-languages=c,ada,c++,go,d,fortran,objc,obj-c++,m2 --prefix=/usr --with-gcc-major-version-only --program-suffix=-10 --program-prefix=aarch64-linux-gnu- --enable-shared --enable-linker-build-id --libexecdir=/usr/lib --without-included-gettext --enable-threads=posix --libdir=/usr/lib --enable-nls --enable-bootstrap --enable-clocale=gnu --enable-libstdcxx-debug --enable-libstdcxx-time=yes --with-default-libstdcxx-abi=new --enable-gnu-unique-object --disable-libquadmath --disable-libquadmath-support --enable-plugin --enable-default-pie --with-system-zlib --enable-libphobos-checking=release --with-target-system-zlib=auto --enable-objc-gc=auto --enable-multiarch --enable-fix-cortex-a53-843419 --disable-werror --enable-checking=release --build=aarch64-linux-gnu --host=aarch64-linux-gnu --target=aarch64-linux-gnu --with-build-config=bootstrap-lto-lean --enable-link-mutex
Thread model: posix
Supported LTO compression algorithms: zlib zstd
gcc version 10.2.1 20210110 (Debian 10.2.1-6)
```

Result :
```bash
________________________________________________________
Executed in   41.63 mins   fish           external
   usr time  1003.51 secs    0.00 millis  1003.51 secs
   sys time  526.66 secs    3.15 millis  526.66 secs
```
