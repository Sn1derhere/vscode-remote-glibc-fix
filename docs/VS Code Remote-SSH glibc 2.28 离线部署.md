# VS Code Remote-SSH glibc 2.28 离线部署

适用：x86_64、glibc 低于 2.28 的 Linux（CentOS / RHEL 7 等），VS Code 1.99+，已安装 **Remote - SSH** 扩展。

原理：不动系统 glibc，只让 VS Code Server 使用 `~/.vscode-server/sysroot` 里的 glibc 2.28。

## 三步完成

**1. 在项目根目录打开 PowerShell（能看到 `README.md` 和 `deploy.sh` 的那层），上传压缩包和脚本**

```pwsh
scp ".\packages\vscode-sysroot-x86_64-linux-gnu.tgz" ".\deploy.sh" root@<工控机IP>:~/
```

**2. 登录并运行脚本**

```pwsh
ssh root@<工控机IP> "sh ~/deploy.sh"
```

脚本依次完成：校验 SHA-256 → 解压 sysroot → 验证 glibc/patchelf → 写 3 个环境变量 → 挂到 `.bashrc`。最后打印 `完成：回到 VS Code 重新连接即可。` 即成功；中途报错就停下来看文末排错。

**3. 用 VS Code Remote-SSH 重新连接**

先关掉当前的远程窗口，再重新连接。`输出 → Remote - SSH` 中出现下面两行即成功：

```
Patching glibc
Patching linker
```

完成。下面内容只在脚本跑不通或需要手工操作时看。

## 手动步骤（脚本做的事）

```bash
sha256sum /root/vscode-sysroot-x86_64-linux-gnu.tgz
# 正确值 d9cb792a650d5b9497422477ae69e96751ad86619d7d1a8b3792b64995c80dac

mkdir -p /root/.vscode-server
tar -xzf /root/vscode-sysroot-x86_64-linux-gnu.tgz -C /root/.vscode-server

SYSROOT=/root/.vscode-server/sysroot
"$SYSROOT/lib/ld-linux-x86-64.so.2" --library-path "$SYSROOT/lib:$SYSROOT/usr/lib" /bin/echo "glibc 2.28 OK"
"$SYSROOT/usr/bin/patchelf" --version

cat > /root/.vscode-server/sysroot.sh <<'EOF'
#!/bin/bash
export VSCODE_SERVER_CUSTOM_GLIBC_LINKER="/root/.vscode-server/sysroot/lib/ld-linux-x86-64.so.2"
export VSCODE_SERVER_CUSTOM_GLIBC_PATH="/root/.vscode-server/sysroot/lib:/root/.vscode-server/sysroot/usr/lib"
export VSCODE_SERVER_PATCHELF_PATH="/root/.vscode-server/sysroot/usr/bin/patchelf"
EOF

[ -f /root/.bashrc ] || touch /root/.bashrc
grep -q 'vscode-server/sysroot.sh' /root/.bashrc || {
  cp /root/.bashrc /root/.bashrc.backup-before-vscode
  sed -i '1i [ -f /root/.vscode-server/sysroot.sh ] && source /root/.vscode-server/sysroot.sh' /root/.bashrc
}

bash -lc 'env | grep VSCODE_SERVER'
```

最后一条命令应打印 3 个 `VSCODE_SERVER_` 变量。

## 其它情况

- **非 root 账号**：把命令里的 `root@` 换成你的用户名即可，`deploy.sh` 自动使用当前用户的 `$HOME`；VS Code 必须用同一个账号连接。手动步骤里的 `/root` 要换成 `$HOME`。
- **SSH 不是 22 端口**：`ssh` 加 `-p <端口>`，`scp` 加 `-P <端口>`。
- **登录 shell 是 zsh**：把 `source` 那行加到 `~/.zshrc` 首行；`bash -lc` 仍无效就加到 `~/.bash_profile`。
- **不是 x86_64**：`uname -m` 不是 `x86_64` 就用不了这个包。
- **目标机完全离线**：首次连接仍需下载 VS Code Server，本方案只解决 glibc 兼容。

## 排错

| 现象 | 处理 |
|---|---|
| 没有 Patching 输出 | 运行 `bash -lc 'env \| grep VSCODE_SERVER'`，没有 3 个变量就检查 `.bashrc` 首行 |
| `GLIBC_2.28 not found` | sysroot 路径写错，或变量没生效 |
| 改了配置仍不生效 | `rm -rf /root/.vscode-server/bin` 后重连 |
| `patchelf: cannot execute binary file` | 架构不是 x86_64 |

回滚：

```bash
mv -f /root/.bashrc.backup-before-vscode /root/.bashrc
rm -rf /root/.vscode-server/sysroot /root/.vscode-server/sysroot.sh
```
