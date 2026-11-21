# vscode-glibc-sysroot

让 VS Code Remote-SSH / Dev Containers 连接 **glibc 2.28 老版本 Linux**（CentOS 7.9 / RHEL 7.9 / Oracle Linux 7.9、以及基于这些基础镜像的工控机容器）的离线部署资料包。

核心思路：**不动系统原有 glibc**，单独放一份 glibc 2.28 的 sysroot，通过 3 个环境变量让 VS Code Server 启动时用 patchelf 把自己指向这份新 glibc。

```bash
export VSCODE_SERVER_CUSTOM_GLIBC_LINKER="<sysroot>/lib/ld-linux-x86-64.so.2"
export VSCODE_SERVER_CUSTOM_GLIBC_PATH="<sysroot>/lib:<sysroot>/usr/lib"
export VSCODE_SERVER_PATCHELF_PATH="<sysroot>/usr/bin/patchelf"
```

## 目录结构

```
vscode-glibc-sysroot/
├── README.md                                  本文件：资料索引
├── deploy.sh                                  工控机一键部署脚本（校验 → 解压 → 验证 → 写环境变量）
├── docs/
│   ├── VS Code Remote-SSH glibc 2.28 离线部署.md   ← 物理机 / 工控机部署
│   └── 容器内部署 VS Code glibc 2.28 sysroot.md    ← Docker 容器内部署
├── packages/
│   └── vscode-sysroot-x86_64-linux-gnu.tgz         ★ 最终部署包（31.9 MB）
└── build/
    └── vscode-sysroot-main/                       构建源码（Dockerfile / Makefile / 配置）
        ├── Dockerfile                             构建时自动下载 crosstool-ng 与 patchelf
        ├── Makefile
        ├── sysroot.sh                             环境变量脚本（$HOME 版本）
        └── x86_64-gcc-8.5.0-glibc-2.28.config     glibc 2.28 + 内核 3.10
```

## 环境要求

- 目标机器 / 容器：**x86_64**，glibc **低于 2.28**（`ldd --version` 确认）
- 本地：Windows 10+ 自带 `ssh` / `scp`
- VS Code **1.99+**，并装好 **Remote - SSH**（容器场景用 **Dev Containers**）扩展
- 目标机首次连接需访问 `update.code.visualstudio.com` 下载 VS Code Server；本方案不包含 Server 的离线分发

## 怎么用

### 场景一：直接连工控机（物理机 / 虚拟机）

详见 [docs/VS Code Remote-SSH glibc 2.28 离线部署.md](docs/VS%20Code%20Remote-SSH%20glibc%202.28%20离线部署.md)。

```pwsh
scp ".\packages\vscode-sysroot-x86_64-linux-gnu.tgz" ".\deploy.sh" root@<工控机IP>:~/
ssh root@<工控机IP> "sh ~/deploy.sh"
```

然后 VS Code 重连，`输出 → Remote - SSH` 出现 `Patching glibc` / `Patching linker` 即成功。不想用脚本时，文档里有一整段可复制的等价手动命令。

### 场景二：连 Docker 容器

详见 [docs/容器内部署 VS Code glibc 2.28 sysroot.md](docs/容器内部署%20VS%20Code%20glibc%202.28%20sysroot.md)。主路线 5 步：

1. scp 到宿主机
2. `docker cp` 进容器
3. 容器内解压并验证
4. `docker commit --change 'ENV ...'` 固化变量
5. 用新镜像重建容器并连接

### 重新构建 sysroot 包

`build/vscode-sysroot-main/` 是上游 `vscode-sysroot` 工程：装好 Docker 后在目录里 `make`，产物为 `toolchain/vscode-sysroot-x86_64-linux-gnu.tgz`。配置为 glibc 2.28 + kernel 3.10（CentOS 7 系列）。Ubuntu 18.04 需要把 config 里的 `CT_LINUX_VERSION` / `CT_GLIBC_MIN_KERNEL` 改成 `4.15`。

构建源码里没有任何本机或工控机的私有参数：所有路径均基于 `CT_TOP_DIR` / `$PWD` / `$HOME`，下载地址只有 GitHub 和各项目官方镜像，可以直接换机器重建。

## 校验值（SHA-256）

| 文件 | SHA-256 |
|---|---|
| `packages/vscode-sysroot-x86_64-linux-gnu.tgz` | `d9cb792a650d5b9497422477ae69e96751ad86619d7d1a8b3792b64995c80dac` |

PowerShell 校验：

```pwsh
Get-FileHash -Algorithm SHA256 .\packages\vscode-sysroot-x86_64-linux-gnu.tgz
```

## 注意事项

- 方案**不替换**系统 glibc，`ldd --version` 仍是系统原版本，只影响 VS Code Server。
- 环境变量必须在 VS Code 建立 SSH session 前生效（`.bashrc` 首行或镜像 `ENV`），否则不会触发 patching。
- 本机路径一律是**相对路径**（相对本目录），目录整体移动、重命名或换机器都不用改文档；远端路径用 `~/` 或 `$HOME`，root 和非 root 账号都适用。手写命令里出现的 `/root` 只是 root 用户的家目录示例，换成自己的 `$HOME` 即可。
- 文档里的 `<工控机IP>`、`<容器名>`、`<registry>/<namespace>/<image>:<tag>` 都是占位符，请替换成自己的环境，本仓库不包含任何真实内网地址或镜像名。
- `packages/` 里的 sysroot 包（31.9 MB）随仓库一起提交，clone/下载后即可直接使用，不需要额外去 Release 找。GitHub 对超过 50 MB 的文件会给出提示，但仍可正常提交。
