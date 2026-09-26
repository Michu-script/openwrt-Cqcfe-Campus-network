# 📦 Releases

这个目录用于存放已经编译好的 OpenWrt 发行包和对应校验文件。

当前版本：

- [v1.0.0](./v1.0.0) —— 当前发布版本

包含内容：

- `ipk` 安装包
- `sha256` 校验文件

安装前建议先校验哈希值，然后在路由器上执行：

```sh
sha256sum luci-app-campus-portal_1.0.0-1_all.ipk
opkg install luci-app-campus-portal_1.0.0-1_all.ipk
/etc/init.d/campus_portal enable
/etc/init.d/campus_portal start
```
