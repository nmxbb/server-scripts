#!/bin/bash

# ==============================================================================
# SSH 安全设置自动化脚本 - ssh-key-only.sh
#
# 功能:
# 1. 确保 .ssh 目录和 authorized_keys 文件存在且权限正确。
# 2. 清理 authorized_keys，注释掉无效的条目。
# 3. 添加预设的 SSH 公钥列表。
# 4. 修改 SSHD 服务器配置，强制使用密钥登录并禁用密码登录。
# 5. 重启 SSH 服务使配置生效。
#
# ==============================================================================

# --- 函数定义 ---

# 检查 .ssh 目录和 authorized_keys 文件，并设置正确权限
setup_ssh_directory() {
  local ssh_dir="$HOME/.ssh"
  local key_file="$ssh_dir/authorized_keys"

  # 确保 .ssh 目录存在且权限为 700
  if [ ! -d "$ssh_dir" ]; then
    echo "创建 .ssh 目录..."
    mkdir -p "$ssh_dir"
    chmod 0700 "$ssh_dir"
  fi

  # 确保 authorized_keys 文件存在且权限为 600
  if [ ! -e "$key_file" ]; then
    echo "创建 authorized_keys 文件..."
    touch "$key_file"
    chmod 0600 "$key_file"
  fi
}

# 注释掉 authorized_keys 文件中不符合密钥格式的行
clean_authorized_keys() {
  local key_file="$HOME/.ssh/authorized_keys"
  local backup_file="$HOME/.ssh/authorized_keys.bak"

  # 如果文件不存在，则无需清理
  if [ ! -f "$key_file" ]; then
    echo "authorized_keys 文件不存在，跳过清理。"
    return
  fi
  
  echo "正在清理 authorized_keys 文件..."
  # 备份 authorized_keys 文件
  cp "$key_file" "$backup_file"

  # 过滤有效的密钥格式，注释掉无效行
  awk '{
    # 如果行以 # 开头，或以 ssh-rsa/dsa/ecdsa/ed25519 开头，则视为有效行
    if ($1 ~ /^(#|ssh-(rsa|dsa|ecdsa|ed25519))/) {
        print $0
    } else {
        # 否则视为无效格式，添加#将其注释掉
        print "#" $0 " # Invalid Key Format by script"
    }
  }' "$backup_file" > "$key_file"

  echo "无效的 SSH 密钥已被注释。"
}

# 添加指定的 SSH 公钥到 authorized_keys（如果不存在）
add_ssh_key_if_not_exists() {
  local ssh_key="$1"
  local key_file="$HOME/.ssh/authorized_keys"

  # 检查公钥是否已存在于文件中
  if grep -qF "$ssh_key" "$key_file"; then
    echo "SSH 公钥已存在，跳过添加。"
  else
    echo "$ssh_key" >> "$key_file"
    echo "SSH 公钥已添加。"
  fi
}

# 修改 sshd_config 配置以增强安全性
configure_sshd() {
  local sshd_config="/etc/ssh/sshd_config"

  # 检查是否有权限编辑配置文件，此部分需要 root 权限
  if [ ! -w "$sshd_config" ]; then
    echo "错误: 没有权限编辑 $sshd_config。请以 root 用户身份运行此脚本。"
    exit 1
  fi

  echo "正在配置 SSHD 服务..."

  # 确保启用公钥认证
  if ! grep -qE "^PubkeyAuthentication yes" "$sshd_config"; then
    # 删除所有旧的 PubkeyAuthentication 设置行，然后添加正确的设置
    sed -i '/^#*PubkeyAuthentication /d' "$sshd_config"
    echo "PubkeyAuthentication yes" >> "$sshd_config"
    echo "已启用公钥认证 (PubkeyAuthentication)。"
  fi

  # 禁用密码认证
  if grep -qE "^PasswordAuthentication yes" "$sshd_config"; then
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' "$sshd_config"
    echo "已禁用密码认证 (PasswordAuthentication)。"
  elif grep -qE "^#PasswordAuthentication yes" "$sshd_config"; then
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' "$sshd_config"
    echo "已禁用密码认证 (PasswordAuthentication)。"
  else
    echo "密码认证已被禁用或未明确启用。"
  fi

  # 重启 SSH 服务以应用配置
  echo "正在尝试重启 SSH 服务..."
  if command -v systemctl > /dev/null; then
    if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
      systemctl restart sshd || systemctl restart ssh
      echo "SSH 服务已通过 systemctl 重启。"
    else
      echo "SSH 服务当前未激活，未执行重启。"
    fi
  elif command -v service > /dev/null; then
    service ssh restart
    echo "SSH 服务已通过 service 重启。"
  else
    echo "错误: 无法自动重启 SSH 服务。请在脚本执行后手动重启。"
  fi
}

# --- 主函数 ---
main() {
  echo "--- 开始执行 SSH 安全设置 ---"
  
  # 步骤 1: 设置 SSH 目录和文件
  setup_ssh_directory
  
  # 步骤 2: 清理现有的 authorized_keys 文件
  clean_authorized_keys
  
  # 步骤 3: 添加你的 SSH 公钥列表
  # 下面的列表已更新为你提供的公钥。
  # 如果你还有其他公钥需要添加，可以仿照这个格式继续添加。
  local SSH_KEYS=(
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcks0HZtjxxQoC0Hbn3LG/KFXc8sNVOPpfMO7oMJcdc common"
  )
  
  echo "正在添加预设的 SSH 公KEY..."
  for key in "${SSH_KEYS[@]}"; do
    add_ssh_key_if_not_exists "$key"
  done
  
  # 步骤 4: 配置并重启 SSHD 服务 (需要 root 权限)
  configure_sshd
  
  echo "--- SSH 安全设置执行完毕 ---"
  echo "重要提示：请确保你已添加了正确的公钥，并尝试从新终端登录以验证设置是否成功，然后再断开当前连接。"
}

# --- 脚本入口 ---
main