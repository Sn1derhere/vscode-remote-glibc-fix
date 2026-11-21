#!/bin/sh
set -e
PKG=${1:-$HOME/vscode-sysroot-x86_64-linux-gnu.tgz}
EXPECT=d9cb792a650d5b9497422477ae69e96751ad86619d7d1a8b3792b64995c80dac
SERVER_DIR="$HOME/.vscode-server"
BASHRC="$HOME/.bashrc"

echo "=== 1. 校验压缩包 ==="
[ -f "$PKG" ] || { echo "找不到压缩包：$PKG"; exit 1; }
[ "$(uname -m)" = "x86_64" ] || { echo "当前架构是 $(uname -m)，本包只支持 x86_64"; exit 1; }
ACTUAL=$(sha256sum "$PKG" | awk '{print $1}')
echo "sha256: $ACTUAL"
[ "$ACTUAL" = "$EXPECT" ] || { echo "校验失败，停止"; exit 1; }

echo "=== 2. 解压 sysroot ==="
mkdir -p "$SERVER_DIR"
rm -rf "$SERVER_DIR/sysroot"
tar -xzf "$PKG" -C "$SERVER_DIR"
ls -ld "$SERVER_DIR/sysroot"

echo "=== 3. 验证 glibc 2.28 ==="
SYSROOT="$SERVER_DIR/sysroot"
LOADER="$SYSROOT/lib/ld-linux-x86-64.so.2"
LIBPATH="$SYSROOT/lib:$SYSROOT/usr/lib"
"$LOADER" --library-path "$LIBPATH" /bin/true && echo "loader exit=0"
"$LOADER" --library-path "$LIBPATH" /bin/echo "glibc 2.28 OK"

echo "=== 4. 验证 patchelf ==="
chmod +x "$SYSROOT/usr/bin/patchelf"
"$SYSROOT/usr/bin/patchelf" --version

echo "=== 5. 写入 sysroot.sh ==="
cat > "$SERVER_DIR/sysroot.sh" <<EOF
#!/bin/bash

export VSCODE_SERVER_CUSTOM_GLIBC_LINKER="$SYSROOT/lib/ld-linux-x86-64.so.2"
export VSCODE_SERVER_CUSTOM_GLIBC_PATH="$SYSROOT/lib:$SYSROOT/usr/lib"
export VSCODE_SERVER_PATCHELF_PATH="$SYSROOT/usr/bin/patchelf"
EOF
chmod +x "$SERVER_DIR/sysroot.sh"

echo "=== 6. 挂到 .bashrc 首行 ==="
[ -f "$BASHRC" ] || touch "$BASHRC"
if grep -q 'vscode-server/sysroot.sh' "$BASHRC"; then
  echo "已存在，跳过"
else
  cp "$BASHRC" "$BASHRC.backup-before-vscode"
  sed -i '1i [ -f "$HOME/.vscode-server/sysroot.sh" ] && source "$HOME/.vscode-server/sysroot.sh"' "$BASHRC"
  echo "已写入（备份 $BASHRC.backup-before-vscode）"
fi
head -1 "$BASHRC"

echo "=== 7. 登录式 shell 验证 ==="
if bash -lc 'env | grep VSCODE_SERVER'; then
  echo "环境变量 OK"
else
  echo "警告：登录式 bash 没读到变量，检查 $BASHRC 或 ~/.bash_profile 是否加载 .bashrc。"
fi

echo "=== 8. 删除压缩包 ==="
rm -f "$PKG"

echo "=== 9. 系统 glibc 未变 ==="
ldd --version | head -1
echo "完成：回到 VS Code 重新连接即可。"
