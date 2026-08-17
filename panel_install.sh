#!/bin/bash
set -e

# 解决 macOS 下 tr 可能出现的非法字节序列问题
export LANG=en_US.UTF-8
export LC_ALL=C



# 全局下载地址配置
DOCKER_COMPOSEV4_URL="https://github.com/bqlpfy/flux-panel/releases/download/2.0.7-beta/docker-compose-v4.yml"
DOCKER_COMPOSEV6_URL="https://github.com/bqlpfy/flux-panel/releases/download/2.0.7-beta/docker-compose-v6.yml"

COUNTRY=$(curl -s https://ipinfo.io/country)
if [ "$COUNTRY" = "CN" ]; then
    # 拼接 URL
    DOCKER_COMPOSEV4_URL="https://ghfast.top/${DOCKER_COMPOSEV4_URL}"
    DOCKER_COMPOSEV6_URL="https://ghfast.top/${DOCKER_COMPOSEV6_URL}"
fi



# 根据IPv6支持情况选择docker-compose URL
get_docker_compose_url() {
  if check_ipv6_support > /dev/null 2>&1; then
    echo "$DOCKER_COMPOSEV6_URL"
  else
    echo "$DOCKER_COMPOSEV4_URL"
  fi
}

# 检查 docker-compose 或 docker compose 命令
check_docker() {
  if command -v docker-compose &> /dev/null; then
    DOCKER_CMD="docker-compose"
  elif command -v docker &> /dev/null; then
    if docker compose version &> /dev/null; then
      DOCKER_CMD="docker compose"
    else
      echo "错误：检测到 docker，但不支持 'docker compose' 命令。请安装 docker-compose 或更新 docker 版本。"
      exit 1
    fi
  else
    echo "错误：未检测到 docker 或 docker-compose 命令。请先安装 Docker。"
    exit 1
  fi
  echo "检测到 Docker 命令：$DOCKER_CMD"
}

# 检测系统是否支持 IPv6
check_ipv6_support() {
  echo "🔍 检测 IPv6 支持..."

  # 检查是否有 IPv6 地址（排除 link-local 地址）
  if ip -6 addr show | grep -v "scope link" | grep -q "inet6"; then
    echo "✅ 检测到系统支持 IPv6"
    return 0
  elif ifconfig 2>/dev/null | grep -v "fe80:" | grep -q "inet6"; then
    echo "✅ 检测到系统支持 IPv6"
    return 0
  else
    echo "⚠️ 未检测到 IPv6 支持"
    return 1
  fi
}



# 配置 Docker 启用 IPv6
configure_docker_ipv6() {
  echo "🔧 配置 Docker IPv6 支持..."

  # 检查操作系统类型
  OS_TYPE=$(uname -s)

  if [[ "$OS_TYPE" == "Darwin" ]]; then
    # macOS 上 Docker Desktop 已默认支持 IPv6
    echo "✅ macOS Docker Desktop 默认支持 IPv6"
    return 0
  fi

  # Docker daemon 配置文件路径
  DOCKER_CONFIG="/etc/docker/daemon.json"

  # 检查是否需要 sudo
  if [[ $EUID -ne 0 ]]; then
    SUDO_CMD="sudo"
  else
    SUDO_CMD=""
  fi

  # 检查 Docker 配置文件
  if [ -f "$DOCKER_CONFIG" ]; then
    # 检查是否已经配置了 IPv6
    if grep -q '"ipv6"' "$DOCKER_CONFIG"; then
      echo "✅ Docker 已配置 IPv6 支持"
    else
      echo "📝 更新 Docker 配置以启用 IPv6..."
      # 备份原配置
      $SUDO_CMD cp "$DOCKER_CONFIG" "${DOCKER_CONFIG}.backup"

      # 使用 jq 或 sed 添加 IPv6 配置
      if command -v jq &> /dev/null; then
        $SUDO_CMD jq '. + {"ipv6": true, "fixed-cidr-v6": "fd00::/80"}' "$DOCKER_CONFIG" > /tmp/daemon.json && $SUDO_CMD mv /tmp/daemon.json "$DOCKER_CONFIG"
      else
        # 如果没有 jq，使用 sed
        $SUDO_CMD sed -i 's/^{$/{\n  "ipv6": true,\n  "fixed-cidr-v6": "fd00::\/80",/' "$DOCKER_CONFIG"
      fi

      echo "🔄 重启 Docker 服务..."
      if command -v systemctl &> /dev/null; then
        $SUDO_CMD systemctl restart docker
      elif command -v service &> /dev/null; then
        $SUDO_CMD service docker restart
      else
        echo "⚠️ 请手动重启 Docker 服务"
      fi
      sleep 5
    fi
  else
    # 创建新的配置文件
    echo "📝 创建 Docker 配置文件..."
    $SUDO_CMD mkdir -p /etc/docker
    echo '{
  "ipv6": true,
  "fixed-cidr-v6": "fd00::/80"
}' | $SUDO_CMD tee "$DOCKER_CONFIG" > /dev/null

    echo "🔄 重启 Docker 服务..."
    if command -v systemctl &> /dev/null; then
      $SUDO_CMD systemctl restart docker
    elif command -v service &> /dev/null; then
      $SUDO_CMD service docker restart
    else
      echo "⚠️ 请手动重启 Docker 服务"
    fi
    sleep 5
  fi
}

# 显示菜单
show_menu() {
  echo "==============================================="
  echo "          面板管理脚本"
  echo "==============================================="
  echo "请选择操作："
  echo "1. 安装面板"
  echo "2. 更新面板"
  echo "3. 停止面板"
  echo "4. 启动面板"
  echo "5. 备份数据库"
  echo "6. 恢复数据库"
  echo "7. 卸载面板"
  echo "8. 退出"
  echo "==============================================="
}

generate_random() {
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c16
}

# 获取用户输入的配置参数
get_config_params() {
  echo "🔧 请输入配置参数："

  read -p "前端端口（默认 6366）: " FRONTEND_PORT
  FRONTEND_PORT=${FRONTEND_PORT:-6366}

  read -p "后端端口（默认 6365）: " BACKEND_PORT
  BACKEND_PORT=${BACKEND_PORT:-6365}

  # 生成JWT密钥
  JWT_SECRET=$(generate_random)
}

# 安装功能
install_panel() {
  echo "🚀 开始安装面板..."
  check_docker
  get_config_params

  echo "🔽 下载必要文件..."
  DOCKER_COMPOSE_URL=$(get_docker_compose_url)
  echo "📡 选择配置文件：$(basename "$DOCKER_COMPOSE_URL")"
  curl -L -o docker-compose.yml "$DOCKER_COMPOSE_URL"
  echo "✅ 文件准备完成"

  # 自动检测并配置 IPv6 支持
  if check_ipv6_support; then
    echo "🚀 系统支持 IPv6，自动启用 IPv6 配置..."
    configure_docker_ipv6
  fi

  cat > .env <<EOF
JWT_SECRET=$JWT_SECRET
FRONTEND_PORT=$FRONTEND_PORT
BACKEND_PORT=$BACKEND_PORT
EOF

  echo "🚀 启动 docker 服务..."
  $DOCKER_CMD up -d

  echo "🎉 部署完成"
  echo "🌐 访问地址: http://服务器IP:$FRONTEND_PORT"
  echo "📖 部署完成后请阅读下使用文档，求求了啊，不要上去就是一顿操作"
  echo "📚 文档地址: https://tes.cc/guide.html"
  echo "💡 默认管理员账号: admin_user / admin_user"
  echo "⚠️  登录后请立即修改默认密码！"
}

# 更新功能
update_panel() {
  echo "🔄 开始更新面板..."
  check_docker

  echo "🔽 下载最新配置文件..."
  DOCKER_COMPOSE_URL=$(get_docker_compose_url)
  echo "📡 选择配置文件：$(basename "$DOCKER_COMPOSE_URL")"
  curl -L -o docker-compose.yml "$DOCKER_COMPOSE_URL"
  echo "✅ 下载完成"

  # 自动检测并配置 IPv6 支持
  if check_ipv6_support; then
    echo "🚀 系统支持 IPv6，自动启用 IPv6 配置..."
    configure_docker_ipv6
  fi

  # 先发送 SIGTERM 信号，让应用优雅关闭
  docker stop -t 30 springboot-backend 2>/dev/null || true
  docker stop -t 10 vite-frontend 2>/dev/null || true
  
  # 等待 WAL 文件同步
  echo "⏳ 等待数据同步..."
  sleep 5
  
  # 然后再完全停止
  $DOCKER_CMD down

  echo "⬇️ 拉取最新镜像..."
  $DOCKER_CMD pull

  echo "🚀 启动更新后的服务..."
  $DOCKER_CMD up -d

  # 等待服务启动
  echo "⏳ 等待服务启动..."

  # 检查后端容器健康状态
  echo "🔍 检查后端服务状态..."
  for i in {1..90}; do
    if docker ps --format "{{.Names}}" | grep -q "^springboot-backend$"; then
      BACKEND_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' springboot-backend 2>/dev/null || echo "unknown")
      if [[ "$BACKEND_HEALTH" == "healthy" ]]; then
        echo "✅ 后端服务健康检查通过"
        break
      elif [[ "$BACKEND_HEALTH" == "starting" ]]; then
        # 继续等待
        :
      elif [[ "$BACKEND_HEALTH" == "unhealthy" ]]; then
        echo "⚠️ 后端健康状态：$BACKEND_HEALTH"
      fi
    else
      echo "⚠️ 后端容器未找到或未运行"
      BACKEND_HEALTH="not_running"
    fi
    if [ $i -eq 90 ]; then
      echo "❌ 后端服务启动超时（90秒）"
      echo "🔍 当前状态：$(docker inspect -f '{{.State.Health.Status}}' springboot-backend 2>/dev/null || echo '容器不存在')"
      echo "🛑 更新终止"
      return 1
    fi
    # 每15秒显示一次进度
    if [ $((i % 15)) -eq 1 ]; then
      echo "⏳ 等待后端服务启动... ($i/90) 状态：${BACKEND_HEALTH:-unknown}"
    fi
    sleep 1
  done

  echo "✅ 更新完成"
}

# 停止面板功能
stop_panel() {
  echo "⏹️ 开始停止面板..."
  check_docker

  if [[ ! -f "docker-compose.yml" ]]; then
    echo "⚠️ 未找到 docker-compose.yml 文件"
    echo "💡 请确保在面板安装目录执行此脚本"
    return 1
  fi

  # 检查容器是否在运行
  if ! $DOCKER_CMD ps --services 2>/dev/null | grep -q .; then
    echo "ℹ️ 面板未在运行"
    return 0
  fi

  echo "🛑 正在停止面板服务..."
  
  # 先优雅停止后端服务（发送 SIGTERM，等待30秒）
  echo "⏳ 优雅停止后端服务..."
  docker stop -t 30 springboot-backend 2>/dev/null || true
  
  # 停止前端服务（等待10秒）
  echo "⏳ 停止前端服务..."
  docker stop -t 10 vite-frontend 2>/dev/null || true
  
  # 停止所有容器
  $DOCKER_CMD down

  echo "✅ 面板已停止"
}

# 启动面板功能
start_panel() {
  echo "▶️ 开始启动面板..."
  check_docker

  if [[ ! -f "docker-compose.yml" ]]; then
    echo "⚠️ 未找到 docker-compose.yml 文件"
    echo "💡 请确保在面板安装目录执行此脚本"
    return 1
  fi

  # 检查 .env 文件是否存在
  if [[ ! -f ".env" ]]; then
    echo "⚠️ 未找到 .env 配置文件"
    echo "💡 请先安装面板或恢复 .env 文件"
    return 1
  fi

  # 检查容器是否已经在运行
  if $DOCKER_CMD ps --services 2>/dev/null | grep -q .; then
    echo "ℹ️ 面板已经在运行中"
    return 0
  fi

  echo "🚀 启动面板服务..."
  $DOCKER_CMD up -d

  # 等待服务启动
  echo "⏳ 等待服务启动..."

  # 检查后端容器健康状态
  echo "🔍 检查后端服务状态..."
  for i in {1..30}; do
    if docker ps --format "{{.Names}}" | grep -q "^springboot-backend$"; then
      BACKEND_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' springboot-backend 2>/dev/null || echo "unknown")
      if [[ "$BACKEND_HEALTH" == "healthy" ]]; then
        echo "✅ 后端服务健康检查通过"
        break
      elif [[ "$BACKEND_HEALTH" == "starting" ]]; then
        # 继续等待
        :
      elif [[ "$BACKEND_HEALTH" == "unhealthy" ]]; then
        echo "⚠️ 后端健康状态：$BACKEND_HEALTH"
      fi
    else
      echo "⚠️ 后端容器未找到或未运行"
      BACKEND_HEALTH="not_running"
    fi
    if [ $i -eq 30 ]; then
      echo "⚠️ 后端服务启动可能较慢，请稍后检查状态"
    fi
    if [ $((i % 10)) -eq 0 ]; then
      echo "⏳ 等待服务启动... ($i/30)"
    fi
    sleep 1
  done

  # 获取端口信息
  if [ -f ".env" ]; then
    FRONTEND_PORT=$(grep FRONTEND_PORT .env | cut -d '=' -f2)
    echo "✅ 面板启动完成"
    echo "🌐 访问地址: http://服务器IP:${FRONTEND_PORT:-6366}"
  else
    echo "✅ 面板启动完成"
  fi
}

# 备份数据库功能
backup_database() {
  echo "💾 开始备份数据库..."
  
  # 数据库文件路径
  DB_PATH="/var/lib/docker/volumes/sqlite_data/_data/gost.db"
  BACKUP_PATH="${DB_PATH}.bak"
  
  # 检查数据库文件是否存在
  if [ ! -f "$DB_PATH" ]; then
    echo "❌ 数据库文件不存在: $DB_PATH"
    echo "💡 请确保面板已安装并运行过"
    return 1
  fi
  
  # 检查面板是否在运行，如果在运行则停止
  if docker ps --format "{{.Names}}" | grep -q "springboot-backend"; then
    echo "⏹️ 面板正在运行，先停止面板..."
    stop_panel
    sleep 2
  else
    echo "ℹ️ 面板未运行"
  fi
  
  # 获取数据库文件大小
  DB_SIZE=$(du -h "$DB_PATH" | cut -f1)
  echo "📊 数据库大小: $DB_SIZE"
  
  # 执行备份（复制文件）
  echo "⏳ 正在备份数据库..."
  if cp "$DB_PATH" "$BACKUP_PATH"; then
    BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
    echo "✅ 备份完成"
    echo "📁 备份文件路径: $BACKUP_PATH"
    echo "📊 备份大小: $BACKUP_SIZE"
    
    # 显示文件详细信息
    ls -lh "$BACKUP_PATH"
  else
    echo "❌ 备份失败"
    return 1
  fi
}

# 恢复数据库功能
restore_database() {
  echo "🔄 开始恢复数据库..."
  
  # 数据库文件路径
  DB_PATH="/var/lib/docker/volumes/sqlite_data/_data/gost.db"
  BACKUP_PATH="${DB_PATH}.bak"
  
  # 检查备份文件是否存在
  if [ ! -f "$BACKUP_PATH" ]; then
    echo "❌ 备份文件不存在: $BACKUP_PATH"
    echo "💡 请先执行备份操作"
    return 1
  fi
  
  # 检查面板是否在运行，如果在运行则停止
  if docker ps --format "{{.Names}}" | grep -q "springboot-backend"; then
    echo "⏹️ 面板正在运行，先停止面板..."
    stop_panel
    sleep 2
  else
    echo "ℹ️ 面板未运行"
  fi
  
  # 显示备份文件信息
  BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
  BACKUP_DATE=$(stat -c "%y" "$BACKUP_PATH" 2>/dev/null | cut -d '.' -f1 || stat -f "%Sm" "$BACKUP_PATH" 2>/dev/null)
  
  echo "📋 备份文件信息:"
  echo "📁 路径: $BACKUP_PATH"
  echo "📊 大小: $BACKUP_SIZE"
  echo "📅 日期: $BACKUP_DATE"
  
  # 确认恢复操作
  echo ""
  read -p "⚠️ 恢复操作将覆盖现有数据库，确认继续? (y/N): " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "❌ 取消恢复操作"
    return 0
  fi
  
  # 如果存在当前数据库，先备份当前数据库（以防万一）
  if [ -f "$DB_PATH" ]; then
    CURRENT_BACKUP="${DB_PATH}.current_bak"
    echo "📦 备份当前数据库到: $CURRENT_BACKUP"
    cp "$DB_PATH" "$CURRENT_BACKUP"
  fi
  
  # 执行恢复（复制备份文件到数据库文件）
  echo "⏳ 正在恢复数据库..."
  if cp "$BACKUP_PATH" "$DB_PATH"; then
    echo "✅ 数据库恢复成功"
    echo "📁 恢复文件: $DB_PATH"
    
    # 显示恢复后的文件信息
    RESTORE_SIZE=$(du -h "$DB_PATH" | cut -f1)
    echo "📊 恢复后大小: $RESTORE_SIZE"
    
    # 启动面板
    echo "▶️ 启动面板..."
    start_panel
    
    echo "✅ 数据库恢复完成"
  else
    echo "❌ 数据库恢复失败"
    # 如果恢复失败，尝试恢复之前的备份
    if [ -f "$CURRENT_BACKUP" ]; then
      echo "🔄 尝试恢复原来的数据库..."
      cp "$CURRENT_BACKUP" "$DB_PATH"
      echo "✅ 已恢复原来的数据库"
    fi
    return 1
  fi
}

# 卸载功能
uninstall_panel() {
  echo "🗑️ 开始卸载面板..."
  check_docker

  if [[ ! -f "docker-compose.yml" ]]; then
    echo "⚠️ 未找到 docker-compose.yml 文件，正在下载以完成卸载..."
    DOCKER_COMPOSE_URL=$(get_docker_compose_url)
    echo "📡 选择配置文件：$(basename "$DOCKER_COMPOSE_URL")"
    curl -L -o docker-compose.yml "$DOCKER_COMPOSE_URL"
    echo "✅ docker-compose.yml 下载完成"
  fi

  read -p "确认卸载面板吗？此操作将停止并删除所有容器和数据 (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ 取消卸载"
    return 0
  fi

  echo "🛑 停止并删除容器、镜像、卷..."
  $DOCKER_CMD down --rmi all --volumes --remove-orphans
  echo "🧹 删除配置文件..."
  rm -f docker-compose.yml .env
  echo "✅ 卸载完成"
}

# 主逻辑
main() {

  # 显示交互式菜单
  while true; do
    show_menu
    read -p "请输入选项 (1-8): " choice

    case $choice in
      1)
        install_panel
        echo ""
        echo "✅ 安装完成！脚本保留在当前目录。"
        exit 0
        ;;
      2)
        update_panel
        echo ""
        echo "✅ 更新完成！脚本保留在当前目录。"
        exit 0
        ;;
      3)
        stop_panel
        echo ""
        echo "✅ 停止完成！"
        ;;
      4)
        start_panel
        echo ""
        echo "✅ 启动完成！"
        ;;
      5)
        backup_database
        echo ""
        echo "✅ 备份操作完成！"
        ;;
      6)
        restore_database
        echo ""
        echo "✅ 恢复操作完成！"
        ;;
      7)
        uninstall_panel
        echo ""
        echo "✅ 卸载完成！脚本保留在当前目录。"
        exit 0
        ;;
      8)
        echo "👋 退出脚本"
        exit 0
        ;;
      *)
        echo "❌ 无效选项，请输入 1-8"
        echo ""
        ;;
    esac
  done
}

# 执行主函数
main
