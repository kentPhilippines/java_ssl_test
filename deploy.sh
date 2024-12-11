#!/bin/bash

# 基础配置
APP_NAME="ssl-test-project"
APP_USER="$(whoami)"
APP_GROUP="$(id -gn)"
INSTALL_DIR="/opt/${APP_NAME}"
LOG_DIR="/var/log/${APP_NAME}"
BACKUP_DIR="${INSTALL_DIR}/backup"
DATA_DIR="${INSTALL_DIR}/data"
JDK_VERSION="11"

# Git相关配置
GIT_REPO="https://github.com/your-org/ssl-test-project.git"
GIT_BRANCH="main"
VERSION_FILE="${INSTALL_DIR}/VERSION"

# Maven配置
MAVEN_OPTS="-Xmx512m"

# 应用配置
APP_OPTS="-Xmx1G -Xms512m"
APP_PORT="8443"
HTTP_PORT="80"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查系统要求
check_system_requirements() {
    log_info "检查系统要求..."
    
    # 检查操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "操作系统: $NAME $VERSION_ID"
    else
        log_error "无法确定操作系统版本"
        return 1
    fi
    
    # 检查内存
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ $total_mem -lt 1024 ]; then
        log_error "内存不足，需要至少1GB内存"
        return 1
    fi
    
    # 检查磁盘空间
    local free_space=$(df -m ${INSTALL_DIR} | awk 'NR==2 {print $4}')
    if [ $free_space -lt 1024 ]; then
        log_error "磁盘空间不足，需要至少1GB可用空间"
        return 1
    fi
}

# 安装依赖
install_dependencies() {
    log_info "安装依赖..."
    
    if [ -f /etc/debian_version ]; then
        sudo apt-get update
        sudo apt-get install -y openjdk-${JDK_VERSION}-jdk maven git curl
    elif [ -f /etc/redhat-release ]; then
        sudo yum update
        sudo yum install -y java-${JDK_VERSION}-openjdk-devel maven git curl
    else
        log_error "不支持的操作系统"
        exit 1
    fi
    
    # 验证安装
    java -version
    mvn -version
    git --version
}

# 配置环境
setup_environment() {
    log_info "配置环境..."
    
    # 创建目录
    sudo mkdir -p ${INSTALL_DIR}/{bin,conf,logs,data,backup,source}
    sudo chown -R ${APP_USER}:${APP_GROUP} ${INSTALL_DIR}
    
    # 配置环境变量
    cat > ${INSTALL_DIR}/conf/env.conf << EOF
JAVA_HOME=$(readlink -f /usr/bin/java | sed "s:/bin/java::")
MAVEN_OPTS="${MAVEN_OPTS}"
APP_OPTS="${APP_OPTS}"
EOF
    chmod 600 ${INSTALL_DIR}/conf/env.conf
    
    # 配置应用属性
    cat > ${INSTALL_DIR}/conf/application.yml << EOF
server:
  port: ${APP_PORT}
  http:
    port: ${HTTP_PORT}
  ssl:
    enabled: false

spring:
  datasource:
    url: jdbc:h2:file:${DATA_DIR}/certdb
    username: sa
    password: password
  jpa:
    hibernate:
      ddl-auto: update

acme:
  server:
    url: https://acme-v02.api.letsencrypt.org/directory
  account:
    email: admin@example.com
  security:
    key-store-type: PKCS12
    key-store-password: changeit
    allow-http: true

logging:
  level:
    com.ssltest: DEBUG
EOF
}

# 创建系统服务
create_service() {
    log_info "创建系统服务..."
    
    cat > /tmp/${APP_NAME}.service << EOF
[Unit]
Description=${APP_NAME} Service
After=network.target

[Service]
User=${APP_USER}
Group=${APP_GROUP}
Type=simple
EnvironmentFile=${INSTALL_DIR}/conf/env.conf
ExecStart=/usr/bin/java \$APP_OPTS \\
    -jar ${INSTALL_DIR}/${APP_NAME}.jar \\
    --spring.config.location=file:${INSTALL_DIR}/conf/application.yml
WorkingDirectory=${INSTALL_DIR}
Restart=always
RestartSec=10
StandardOutput=append:${LOG_DIR}/stdout.log
StandardError=append:${LOG_DIR}/stderr.log

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /tmp/${APP_NAME}.service /etc/systemd/system/
    sudo systemctl daemon-reload
}

# 构建应用
build_application() {
    log_info "构建应用..."
    
    cd "${INSTALL_DIR}/source"
    export MAVEN_OPTS="${MAVEN_OPTS}"
    
    if ! mvn clean package -DskipTests; then
        log_error "构建失败"
        return 1
    fi
    
    cp "target/${APP_NAME}.jar" "${INSTALL_DIR}/"
    git rev-parse HEAD > ${VERSION_FILE}
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    if command -v ufw &> /dev/null; then
        sudo ufw allow ${HTTP_PORT}/tcp
        sudo ufw allow ${APP_PORT}/tcp
    elif command -v firewall-cmd &> /dev/null; then
        sudo firewall-cmd --permanent --add-port=${HTTP_PORT}/tcp
        sudo firewall-cmd --permanent --add-port=${APP_PORT}/tcp
        sudo firewall-cmd --reload
    fi
}

# 配置日志轮转
configure_logrotate() {
    log_info "配置日志轮转..."
    
    cat > /tmp/${APP_NAME}-logrotate << EOF
${LOG_DIR}/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 ${APP_USER} ${APP_GROUP}
    postrotate
        systemctl restart ${APP_NAME}
    endscript
}
EOF

    sudo mv /tmp/${APP_NAME}-logrotate /etc/logrotate.d/${APP_NAME}
}

# 安装应用
install_application() {
    log_info "开始安装应用..."
    
    check_system_requirements || exit 1
    install_dependencies
    setup_environment
    
    # 克隆代码
    git clone -b ${GIT_BRANCH} ${GIT_REPO} "${INSTALL_DIR}/source"
    
    build_application
    create_service
    configure_firewall
    configure_logrotate
    
    start_application
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 未安装"
        return 1
    fi
}

# 启动应用
start_application() {
    log_info "启动应用..."
    sudo systemctl start ${APP_NAME}
    sleep 5
    check_application_status
}

# 停止应用
stop_application() {
    log_info "停止应用..."
    sudo systemctl stop ${APP_NAME}
}

# 检查应用状态
check_application_status() {
    if sudo systemctl is-active ${APP_NAME} &> /dev/null; then
        log_info "应用运行正常"
        return 0
    else
        log_error "应用未运行"
        return 1
    fi
}

# 备份当前版本
backup_current_version() {
    local backup_file="$1"
    log_info "备份当前版本到 ${backup_file}"
    cp "${INSTALL_DIR}/${APP_NAME}.jar" "${backup_file}"
}

# 创建回滚脚本
create_rollback_script() {
    local version="$1"
    local backup_file="$2"
    
    cat > ${ROLLBACK_SCRIPT} << EOF
#!/bin/bash
echo "回滚到版本 ${version}"
sudo systemctl stop ${APP_NAME}
cp "${backup_file}" "${INSTALL_DIR}/${APP_NAME}.jar"
sudo systemctl start ${APP_NAME}
EOF
    
    chmod +x ${ROLLBACK_SCRIPT}
}

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    echo -e "${BLUE}SSL测试项目部署脚本${NC}"
    echo
    echo -e "${YELLOW}用法:${NC}"
    echo "  $0 <命令> [参数]"
    echo
    echo "命令:"
    echo "  install        首次安装应用"
    echo "  update        更新应用到最新版本"
    echo "  start         启动应用"
    echo "  stop          停止应用"
    echo "  restart       重启应用"
    echo "  status        查看应用状态"
    echo "  version       显示版本信息"
    echo "  rollback <版本> 回滚到指定版本"
    echo "  cleanup       清理环境"
    echo
    echo -e "${YELLOW}示例:${NC}"
    echo "  $0 install          # 首次安装"
    echo "  $0 update           # 更新到最新版本"
    echo "  $0 rollback abc123f # 回滚到指定版本"
}

# 版本信息
version_info() {
    if [ -f "${VERSION_FILE}" ]; then
        local current_version=$(cat ${VERSION_FILE})
        echo -e "${BLUE}当前版本:${NC} ${current_version}"
        
        if [ -d "${INSTALL_DIR}/source/.git" ]; then
            cd "${INSTALL_DIR}/source"
            echo -e "${BLUE}可用版本:${NC}"
            git log --oneline -n 5
        fi
    else
        log_error "未找到版本信息"
        return 1
    fi
}

# 回滚版本
rollback() {
    local version="$1"
    if [ -z "$version" ]; then
        log_error "请指定要回滚的版本"
        return 1
    fi
    
    local backup_file="${BACKUP_DIR}/${APP_NAME}-${version}.jar"
    if [ ! -f "${backup_file}" ]; then
        log_error "未找到版本 ${version} 的备份"
        return 1
    fi
    
    echo -e "${RED}警告: 即将回滚到版本 ${version}${NC}"
    read -p "确认回滚? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    
    stop_application
    cp "${backup_file}" "${INSTALL_DIR}/${APP_NAME}.jar"
    start_application
}

# 清理环境
cleanup_environment() {
    echo -e "${RED}警告: 此操作将清理所有应用数据!${NC}"
    echo -e "${YELLOW}将清理以下内容:${NC}"
    echo "1. 应用程序文件"
    echo "2. 日志文件"
    echo "3. 系统服务配置"
    echo "4. 端口配置"
    echo
    
    read -p "确认清理环境? (输入 'YES' 确认) " -r
    echo
    if [[ ! $REPLY == "YES" ]]; then
        log_info "操作已取消"
        return 1
    fi
    
    stop_application
    sudo rm -rf ${INSTALL_DIR} ${LOG_DIR}
    sudo rm -f /etc/systemd/system/${APP_NAME}.service
    sudo systemctl daemon-reload
    
    log_info "环境清理完成"
}

# 主函数
main() {
    case "$1" in
        install)
            install_application
            ;;
        update)
            update_application
            ;;
        start)
            start_application
            ;;
        stop)
            stop_application
            ;;
        restart)
            stop_application
            start_application
            ;;
        status)
            check_application_status
            ;;
        cleanup)
            cleanup_environment
            ;;
        version)
            version_info
            ;;
        rollback)
            rollback "$2"
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

# 如果没有参数，显示帮助信息
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

# 执行主函数
main "$@" 