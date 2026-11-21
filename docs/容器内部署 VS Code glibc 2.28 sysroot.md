# 容器内部署 VS Code glibc 2.28 sysroot

适用：x86_64 容器、glibc 低于 2.28，VS Code 1.99+，已安装 **Dev Containers**（或 Remote - SSH）扩展。

原理：把 sysroot 放进容器，再用 `docker commit` 把 3 个环境变量固化进新镜像；不动容器原 glibc。

## 五步完成

**1. 在项目根目录打开 PowerShell（能看到 `README.md` 的那层），上传到宿主机**

```pwsh
scp ".\packages\vscode-sysroot-x86_64-linux-gnu.tgz" root@<工控机IP>:~/
```

> 会提示输入 SSH 密码，输入时不显示字符是正常的。

**2. 复制进容器并校验**

先用 `docker ps` 确认 `<容器名>`，再执行：

```bash
docker cp ~/vscode-sysroot-x86_64-linux-gnu.tgz <容器名>:/tmp/
docker exec <容器名> sha256sum /tmp/vscode-sysroot-x86_64-linux-gnu.tgz
# 正确值 d9cb792a650d5b9497422477ae69e96751ad86619d7d1a8b3792b64995c80dac
```

**3. 进入容器，安装并验证**

```bash
docker exec -it <容器名> bash
```

在容器内执行：

```bash
mkdir -p /root/.vscode-server
tar -xzf /tmp/vscode-sysroot-x86_64-linux-gnu.tgz -C /root/.vscode-server
rm -f /tmp/vscode-sysroot-x86_64-linux-gnu.tgz

SYSROOT=/root/.vscode-server/sysroot
"$SYSROOT/lib/ld-linux-x86-64.so.2" --library-path "$SYSROOT/lib:$SYSROOT/usr/lib" /bin/echo "glibc 2.28 OK"
"$SYSROOT/usr/bin/patchelf" --version

cat > /root/.vscode-server/sysroot.sh <<'EOF'
#!/bin/bash
export VSCODE_SERVER_CUSTOM_GLIBC_LINKER="/root/.vscode-server/sysroot/lib/ld-linux-x86-64.so.2"
export VSCODE_SERVER_CUSTOM_GLIBC_PATH="/root/.vscode-server/sysroot/lib:/root/.vscode-server/sysroot/usr/lib"
export VSCODE_SERVER_PATCHELF_PATH="/root/.vscode-server/sysroot/usr/bin/patchelf"
EOF

exit
```

**4. 在宿主机提交新镜像**

```bash
docker commit \
  --change 'ENV VSCODE_SERVER_CUSTOM_GLIBC_LINKER=/root/.vscode-server/sysroot/lib/ld-linux-x86-64.so.2' \
  --change 'ENV VSCODE_SERVER_CUSTOM_GLIBC_PATH=/root/.vscode-server/sysroot/lib:/root/.vscode-server/sysroot/usr/lib' \
  --change 'ENV VSCODE_SERVER_PATCHELF_PATH=/root/.vscode-server/sysroot/usr/bin/patchelf' \
  <容器名> <registry>/<namespace>/<image>:<tag>
```

没有私有 registry 时，目标直接写本地名字（如 `myimage:glibc228`）也可以。

**5. 用新镜像启动容器并连接**

```bash
docker run -d --name <新容器名> <registry>/<namespace>/<image>:<tag>
# 端口、挂载、GPU 等按原来的启动参数补全
```

`输出 → Remote - SSH` 中出现 `Patching glibc` 和 `Patching linker` 即成功（连之前先关掉旧的远程窗口）。

## 说明

- 宿主机上任意用户都可以：第 1、2 步用 `~/`，会自动指向你自己的家目录。第 3 步起以容器内 root 为例。
- `docker commit` 会把容器当前所有改动打进镜像，在干净的容器上做。
- 旧容器拿不到环境变量，必须用新镜像重建。
- VS Code 连接的容器用户要与部署用户一致（示例为 root）。
- 容器首次启动 VS Code Server 需要联网下载。

## 排错

| 现象 | 处理 |
|---|---|
| 没有 Patching 输出 | 确认容器来自新镜像：`docker image inspect <image>:<tag> --format '{{range .Config.Env}}{{println .}}{{end}}'` |
| `GLIBC_2.28 not found` | 容器不是 x86_64，或 sysroot 路径不对 |
| 容器里没有 bash | 命令里的 `bash` 换成 `sh` |
