---
title: Zerotier 更改 HOME 目录
articles:
   excerpt_type: html
---


zerotier-one 在启动的时候会建立 `/var/lib/zerotier-one` 作为自己的工作目录，里面存放了zerotier 运行时所需要的配置文件。

但是某些情况下，/var/log 是 tmpfs 挂载后的临时文件，每次重启后会消失，导致 zerotier 找不运行时配置文件，那么 `/var/lib/zerotier-one` 的路径可以更改吗？
<!--more-->

当然可以，在zerotier 代码库里发现这段代码：

```cpp
#ifdef __WINDOWS__
	DWORD bufferSize = 65535;
	std::string userDefinedPath;
	bufferSize = GetEnvironmentVariable("ZEROTIER_HOME", &userDefinedPath[0], bufferSize);
	if (bufferSize) {
		return userDefinedPath;
	}
#else
	if(const char* userDefinedPath = getenv("ZEROTIER_HOME")) {
		return std::string(userDefinedPath);
	}
#endif

	// Finally, resort to using default paths if no user-defined path was provided
#ifdef __UNIX_LIKE__

#ifdef __APPLE__
	// /Library/... on Apple
	return std::string("/Library/Application Support/ZeroTier/One");
#else

#ifdef __BSD__
	// BSD likes /var/db instead of /var/lib
	return std::string("/var/db/zerotier-one");
#else
	// Use /var/lib for Linux and other *nix
	return std::string("/var/lib/zerotier-one");
#endif
```

这段代码依据系统类型来判断 Zerotier home 目录的路径，注意 	`if(const char* userDefinedPath = getenv("ZEROTIER_HOME"))`  这行判断语句给了我们自定义 zerotier home 路径的可能性，设置 `ZEROTIER_HOME` 环境变量指向 zerotier home 位置即可，如 `$(pwd)/zerotier_dir`  ,所以实验一下：

```cpp
$ export ZEROTIER_HOME=$(pwd)/zerotier_dir
$ zerotier-one -d
$ ps aux| grep zerotier # 验证 zerotier 是否成功后台运行
$ ./zerotier-cli listnetworks # 列出加入的zt网络
```
