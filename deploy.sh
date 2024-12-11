#!/bin/bash

# 基础配置
APP_NAME="ssl-test-project"
APP_USER="$(whoami)"
APP_GROUP="$(id -gn)"
INSTALL_DIR="/opt/ssl-java"

# 标准目录结构
APP_JAR="${INSTALL_DIR}/${APP_NAME}.jar"
BACKUP_DIR="${INSTALL_DIR}/backup"
LOG_DIR="${INSTALL_DIR}/logs"
CONF_DIR="${INSTALL_DIR}/conf"
DATA_DIR="${INSTALL_DIR}/data"
SOURCE_DIR="${INSTALL_DIR}/source"

# 工具目录
TOOLS_DIR="${INSTALL_DIR}/tools"
JDK_DIR="${TOOLS_DIR}/jdk"
MAVEN_DIR="${TOOLS_DIR}/maven"

# Git相关配置
GIT_REPO="https://github.com/kentPhilippines/java_ssl_test.git"
GIT_BRANCH="main"
VERSION_FILE="${INSTALL_DIR}/VERSION"

# Maven配置
MAVEN_OPTS="-Xmx512m -Dmaven.repo.local=${INSTALL_DIR}/maven/repository"

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

# 使用绝对路径
JAVA_CMD="${JDK_DIR}/bin/java"
MAVEN_CMD="${MAVEN_DIR}/bin/mvn"

# 添加命令执行日志函数
log_cmd() {
    echo -e "${BLUE}[CMD]${NC} $1"
}

# 完整清理函数
full_cleanup() {
    log_info "执行完整环境清理..."
    
    # 停止服务
    if systemctl is-active --quiet ${APP_NAME}; then
        sudo systemctl stop ${APP_NAME}
        sudo systemctl disable ${APP_NAME}
    fi
    
    # 删除系统服务
    if [ -f "/etc/systemd/system/${APP_NAME}.service" ]; then
        sudo rm -f /etc/systemd/system/${APP_NAME}.service
        sudo systemctl daemon-reload
    fi
    
    # 删除安装目录
    if [ -d "${INSTALL_DIR}" ]; then
        sudo rm -rf "${INSTALL_DIR}"
    fi
    
    # 清理防火墙规则
    if command -v firewall-cmd &> /dev/null; then
        sudo firewall-cmd --permanent --remove-port=${HTTP_PORT}/tcp
        sudo firewall-cmd --permanent --remove-port=${APP_PORT}/tcp
        sudo firewall-cmd --reload
    fi
    
    # 清理日志轮转配置
    if [ -f "/etc/logrotate.d/${APP_NAME}" ]; then
        sudo rm -f "/etc/logrotate.d/${APP_NAME}"
    fi
    
    log_info "环境清理完成"
}

# 创建基础目录
create_base_dir() {
    log_info "创建基础目录..."
    
    # 创建标准目录结构
    local DIRS=(
        "${INSTALL_DIR}"
        "${BACKUP_DIR}"
        "${LOG_DIR}"
        "${CONF_DIR}"
        "${DATA_DIR}"
        "${SOURCE_DIR}"
        "${TOOLS_DIR}"
    )
    
    for dir in "${DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            log_info "创建目录: $dir"
            sudo mkdir -p "$dir"
            sudo chown ${APP_USER}:${APP_GROUP} "$dir"
            sudo chmod 755 "$dir"
        fi
    done
    
    # 特殊权限目录
    sudo chmod 700 "${BACKUP_DIR}"  # 备份目录需要更严格的权限
    sudo chmod 777 "${LOG_DIR}"     # 日志目录需要写入权限
}

# 检查系统要求
check_system_requirements() {
    log_info "检查系统要求..."
    
    # 确保基础目录存在
    create_base_dir
    
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
        log_error "磁盘空间不足，需至少1GB可用空间"
        return 1
    fi
}

# 安装依赖
install_dependencies() {
    log_info "安装依赖..."
    
    # 确保安装目录存在
    sudo mkdir -p ${INSTALL_DIR}/{jdk,maven}
    sudo chown -R ${APP_USER}:${APP_GROUP} ${INSTALL_DIR}
    
    # 检查curl
    if ! command -v curl &> /dev/null; then
        log_error "curl未安装，正在安装..."
        if [ -f /etc/debian_version ]; then
            log_cmd "sudo apt-get install -y curl"
            sudo apt-get install -y curl
        elif [ -f /etc/redhat-release ]; then
            log_cmd "sudo yum install -y curl"
            sudo yum install -y curl
        fi
    fi
    
    # 使用包管理器安装JDK
    log_info "安装JDK..."
    if [ -f /etc/debian_version ]; then
        log_cmd "sudo apt-get update"
        sudo apt-get update
        log_cmd "sudo apt-get install -y openjdk-${JDK_VERSION}-jdk"
        sudo apt-get install -y openjdk-${JDK_VERSION}-jdk
        JDK_PATH="/usr/lib/jvm/java-${JDK_VERSION}-openjdk-amd64"
    elif [ -f /etc/redhat-release ]; then
        # 在RedHat系统中查找JDK路径
        for possible_path in \
            "/usr/lib/jvm/java-${JDK_VERSION}-openjdk" \
            "/usr/lib/jvm/java-${JDK_VERSION}" \
            "/usr/lib/jvm/java-${JDK_VERSION}-openjdk-${JDK_VERSION}.*" \
            "/usr/java/jdk-${JDK_VERSION}"
        do
            if [ -d "${possible_path}" ]; then
                JDK_PATH="${possible_path}"
                break
            fi
        done
        
        # 如果还是找不到，尝试使用find命令
        if [ -z "${JDK_PATH}" ]; then
            JDK_PATH=$(find /usr/lib/jvm/ -maxdepth 1 -type d -name "*openjdk-${JDK_VERSION}*" | head -n 1)
        fi
    fi
    
    # 验证JDK路径
    if [ ! -d "${JDK_PATH}" ]; then
        log_error "JDK路径不存在: ${JDK_PATH}"
        return 1
    fi
    
    log_info "使用JDK路径: ${JDK_PATH}"
    
    # 确保目标目录为空
    if [ -d "${JDK_DIR}" ]; then
        log_cmd "rm -rf ${JDK_DIR}"
        rm -rf "${JDK_DIR}"
    fi
    
    # 创建软链接
    log_cmd "sudo ln -sf ${JDK_PATH} ${JDK_DIR}"
    sudo ln -sf ${JDK_PATH} ${JDK_DIR}
    
    # 验证Java安装（先检查文件是否存在）
    if [ ! -x "${JDK_DIR}/bin/java" ]; then
        log_error "Java可执行文件不存在或无执行权限: ${JDK_DIR}/bin/java"
        return 1
    fi
    
    log_cmd "${JDK_DIR}/bin/java -version"
    if ! "${JDK_DIR}/bin/java" -version; then
        log_error "JDK安装失败"
        return 1
    fi
    
    # 配置环境变量
    export JAVA_HOME=${JDK_DIR}
    export MAVEN_HOME=${MAVEN_DIR}
    export PATH=${JAVA_HOME}/bin:${MAVEN_HOME}/bin:$PATH
    
    # 创建永久环境变量配置
    cat > /tmp/java_env.sh << EOF
export JAVA_HOME=${JDK_DIR}
export MAVEN_HOME=${MAVEN_DIR}
export PATH=\${JAVA_HOME}/bin:\${MAVEN_HOME}/bin:\$PATH
EOF
    
    sudo mv /tmp/java_env.sh /etc/profile.d/
    sudo chmod 644 /etc/profile.d/java_env.sh
    
    # 立即应用环境变量
    source /etc/profile.d/java_env.sh
    
    # 验证安装
    log_cmd "${JAVA_CMD} -version"
    if ! ${JAVA_CMD} -version; then
        log_error "Java 验证失败"
        log_error "JAVA_HOME: ${JAVA_HOME}"
        log_error "PATH: ${PATH}"
        return 1
    fi
    
    # 下载并安装Maven
    log_info "下载Maven..."
    log_cmd "curl -L \"https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz\" -o /tmp/maven.tar.gz"
    curl -L "https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" -o /tmp/maven.tar.gz
    log_cmd "tar -xzf /tmp/maven.tar.gz -C ${MAVEN_DIR} --strip-components=1"
    tar -xzf /tmp/maven.tar.gz -C ${MAVEN_DIR} --strip-components=1
    log_cmd "rm /tmp/maven.tar.gz"
    rm /tmp/maven.tar.gz
    
    # 配置环境变量
    export JAVA_HOME=${JDK_PATH}
    export MAVEN_HOME=${MAVEN_DIR}
    export PATH=${JAVA_HOME}/bin:${MAVEN_HOME}/bin:$PATH
    
    # 验证安装
    if ! java -version; then
        log_error "Java 验证失败"
        return 1
    fi
    
    if ! ${MAVEN_CMD} -version; then
        log_error "Maven 验证失败"
        return 1
    fi
    
    if ! command -v git &> /dev/null; then
        log_error "Git未安装，正在安装..."
        if [ -f /etc/debian_version ]; then
            sudo apt-get install -y git
        elif [ -f /etc/redhat-release ]; then
            sudo yum install -y git
        fi
    fi
    
    git --version
    return 0
}

# 配置环境
setup_environment() {
    log_info "配置环境..."
    
    # 创建配置文件
    mkdir -p "${CONF_DIR}"
    cat > "${CONF_DIR}/application.yml" << EOF
server:
  port: ${APP_PORT}
  http:
    port: ${HTTP_PORT}
  ssl:
    enabled: true
    key-store: ${INSTALL_DIR}/ssl/keystore.p12
    key-store-password: changeit
    key-store-type: PKCS12

spring:
  application:
    name: ${APP_NAME}
  profiles:
    active: prod
  datasource:
    url: jdbc:h2:file:${DATA_DIR}/db/ssl
    username: sa
    password: password
    driver-class-name: org.h2.Driver

logging:
  file:
    path: ${LOG_DIR}
  level:
    root: INFO
    com.ssltest: DEBUG

app:
  data:
    dir: ${DATA_DIR}
  ssl:
    dir: ${DATA_DIR}/ssl
  acme:
    storage-dir: ${DATA_DIR}/acme
EOF

    # 创建数据库目录
    mkdir -p "${DATA_DIR}/db"
    mkdir -p "${DATA_DIR}/ssl"
    mkdir -p "${DATA_DIR}/acme"
    
    # 设置数据目录权限
    chmod 700 "${DATA_DIR}/db"    # 数据库目录需要严格权限
    chmod 700 "${DATA_DIR}/ssl"   # SSL证书目录需要严格权限
    chmod 700 "${DATA_DIR}/acme"  # ACME目录需要严格权限
    chown -R ${APP_USER}:${APP_GROUP} "${DATA_DIR}"
}

# 创建系统服务
create_service() {
    log_info "创建系统服务..."
    
    cat > /tmp/${APP_NAME}.service << EOF
[Unit]
Description=SSL Java Service
After=network.target
Requires=network.target

[Service]
User=${APP_USER}
Group=${APP_GROUP}
Type=simple
Environment=JAVA_HOME=${JDK_DIR}
Environment=PATH=${JDK_DIR}/bin:${MAVEN_DIR}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
WorkingDirectory=${INSTALL_DIR}

# 启动命令
ExecStart=${JDK_DIR}/bin/java \\
    -Xmx1G -Xms512m \\
    -Dserver.port=${APP_PORT} \\
    -Dserver.http.port=${HTTP_PORT} \\
    -Dspring.profiles.active=prod \\
    -Dlogging.file.path=${INSTALL_DIR}/logs \\
    -Dapp.data.dir=${INSTALL_DIR}/data \\
    -Dapp.ssl.dir=${INSTALL_DIR}/ssl \\
    -jar ${INSTALL_DIR}/${APP_NAME}.jar \\
    --spring.config.location=file:${INSTALL_DIR}/conf/application.yml

# 停止命令
ExecStop=/bin/kill -15 \$MAINPID

# 重启策略
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

# 日志配置
StandardOutput=append:${INSTALL_DIR}/logs/stdout.log
StandardError=append:${INSTALL_DIR}/logs/stderr.log

# 资源限制
LimitNOFILE=65535
TimeoutStartSec=180
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /tmp/${APP_NAME}.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable ${APP_NAME}
    
    # 创建默认配置文件
    mkdir -p "${INSTALL_DIR}/conf"
    cat > "${INSTALL_DIR}/conf/application.yml" << EOF
server:
  port: ${APP_PORT}
  http:
    port: ${HTTP_PORT}
  ssl:
    enabled: true
    key-store: ${INSTALL_DIR}/data/keystore.p12
    key-store-password: changeit
    key-store-type: PKCS12

spring:
  application:
    name: ${APP_NAME}
  profiles:
    active: prod

logging:
  file:
    name: ${INSTALL_DIR}/logs/application.log
  level:
    root: INFO
    com.ssltest: DEBUG
EOF
}

# 构建应用
build_application() {
    log_info "构建应用..."
    
    local SOURCE_DIR="${INSTALL_DIR}/source"
    local TARGET_DIR="${SOURCE_DIR}/target"
    local BUILD_LOG="${INSTALL_DIR}/build.log"
    local MAVEN_LOG="${INSTALL_DIR}/maven.log"
    local JAR_NAME="${APP_NAME}-1.0-SNAPSHOT.jar"
    local FINAL_JAR="${INSTALL_DIR}/${APP_NAME}.jar"
    
    # 备份当前运行的JAR
    if [ -f "${FINAL_JAR}" ]; then
        log_info "备份当前JAR文件..."
        cp "${FINAL_JAR}" "${BACKUP_DIR}/${APP_NAME}-$(date +%Y%m%d%H%M%S).jar"
    fi
    
    # 进入源码目录构建
    cd "${SOURCE_DIR}" || {
        log_error "无法进入源码目录"
        return 1
    }
    
    # Maven构建
    log_info "开始构建..."
    if ! ${MAVEN_CMD} clean package -DskipTests > "${BUILD_LOG}" 2>&1; then
        log_error "构建失败，查看日志:"
        cat "${BUILD_LOG}"
        return 1
    fi
    
    # 检查构建产��
    if [ ! -f "${TARGET_DIR}/${JAR_NAME}" ]; then
        log_error "构建产物不存在: ${TARGET_DIR}/${JAR_NAME}"
        log_error "目录内容:"
        ls -l "${TARGET_DIR}"
        return 1
    fi
    
    # 复制到安装目录
    log_cmd "cp ${TARGET_DIR}/${JAR_NAME} ${FINAL_JAR}"
    if ! cp "${TARGET_DIR}/${JAR_NAME}" "${FINAL_JAR}"; then
        log_error "复制JAR文件失败"
        return 1
    fi
    
    # 验证安装目录的JAR
    if ! jar tvf "${FINAL_JAR}" > /dev/null 2>&1; then
        log_error "JAR文件验证失败"
        return 1
    fi
    
    # 清理构建目录
    cd "${INSTALL_DIR}"
    rm -rf "${SOURCE_DIR}/target"
    
    log_info "构建完成: ${FINAL_JAR}"
    ls -l "${FINAL_JAR}"
    
    return 0
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    # 检查防火墙状态
    if ! systemctl is-active --quiet firewalld; then
        log_info "防火墙未运行，正在启动..."
        sudo systemctl start firewalld
    fi
    
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
    
    # 检查日志目录权限
    if [ ! -w "${LOG_DIR}" ]; then
        log_error "没有日志目录写入权限: ${LOG_DIR}"
        return 1
    fi
    
    cat > /tmp/${APP_NAME}-logrotate << EOF
${INSTALL_DIR}/logs/*.log {
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
    
    # 1. 检查并创建必要目录
    local DIRS=(
        "${INSTALL_DIR}"
        "${INSTALL_DIR}/source"
        "${INSTALL_DIR}/maven"
        "${INSTALL_DIR}/jdk"
        "${INSTALL_DIR}/logs"
        "${INSTALL_DIR}/conf"
        "${INSTALL_DIR}/data"
    )
    
    for dir in "${DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            log_info "创建目录: $dir"
            mkdir -p "$dir"
            chown ${APP_USER}:${APP_GROUP} "$dir"
        fi
    done
    
    # 2. 检查Java环境
    if ! check_java_environment; then
        log_error "Java环境检查失败"
        return 1
    fi
    
    # 3. 检查Maven环境
    if ! check_maven_environment; then
        log_error "Maven环境检查失败"
        return 1
    fi
    
    # 4. 克隆代码
    if ! git_clone; then
        log_error "代码克隆失败"
        return 1
    fi
    
    # 5. 构建前检查
    if ! pre_build_check; then
        log_error "构建前检查失败"
        return 1
    fi
    
    # 6. 构建应用
    if ! build_application; then
        log_error "应用构建失败"
        return 1
    fi
    
    # 7. 构建后检查
    if ! post_build_check; then
        log_error "构建后检查失败"
        return 1
    fi
    
    # 创建系统服务
    if ! create_service; then
        return 1
    fi
    
    # 启动应用
    if ! start_application; then
        return 1
    fi
    
    log_info "安装完成"
}

# 检查Java环境
check_java_environment() {
    log_info "检查Java环境..."
    
    if [ ! -x "${JDK_DIR}/bin/java" ]; then
        log_error "Java可执行文件不存在或无执行权限"
        return 1
    fi
    
    "${JDK_DIR}/bin/java" -version || return 1
    return 0
}

# 检查Maven环境
check_maven_environment() {
    log_info "检查Maven环境..."
    
    if [ ! -x "${MAVEN_DIR}/bin/mvn" ]; then
        log_error "Maven可执行文件不存在或无执行权限"
        return 1
    fi
    
    "${MAVEN_DIR}/bin/mvn" -v || return 1
    return 0
}

# 构建前检查
pre_build_check() {
    log_info "构建前检查..."
    
    local SOURCE_DIR="${INSTALL_DIR}/source"
    local POM_FILE="${SOURCE_DIR}/pom.xml"
    local MAIN_CLASS="${SOURCE_DIR}/src/main/java/com/ssltest/SSLTestApplication.java"
    
    # 检查源码目录
    if [ ! -d "${SOURCE_DIR}" ]; then
        log_error "源码目录不存在: ${SOURCE_DIR}"
        return 1
    fi
    
    # 检查pom.xml
    if [ ! -f "${POM_FILE}" ]; then
        log_error "pom.xml不存在: ${POM_FILE}"
        return 1
    fi
    
    # 检查主类文件
    if [ ! -f "${MAIN_CLASS}" ]; then
        log_error "主类文件不存在: ${MAIN_CLASS}"
        return 1
    fi
    
    return 0
}

# 构建后检查
post_build_check() {
    log_info "构建后检查..."
    
    local TARGET_DIR="${INSTALL_DIR}/source/target"
    local JAR_FILE="${TARGET_DIR}/${APP_NAME}.jar"
    
    # 检查构建产物
    if [ ! -f "${JAR_FILE}" ]; then
        log_error "构建产物不存在: ${JAR_FILE}"
        return 1
    fi
    
    # 检查JAR文件大小
    local jar_size=$(stat -f%z "${JAR_FILE}" 2>/dev/null || stat -c%s "${JAR_FILE}")
    if [ "${jar_size}" -lt 1000000 ]; then  # 小于1MB可能有问题
        log_error "JAR文件大小异常: ${jar_size} bytes"
        return 1
    fi
    
    # 验证JAR文件
    if ! jar tvf "${JAR_FILE}" > /dev/null 2>&1; then
        log_error "JAR文件验证失败"
        return 1
    fi
    
    return 0
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
    
    # 检查必要的目录
    local REQUIRED_DIRS=(
        "${DATA_DIR}/db"
        "${DATA_DIR}/ssl"
        "${DATA_DIR}/acme"
        "${LOG_DIR}"
    )
    
    for dir in "${REQUIRED_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            log_error "必要目录不存在: $dir"
            return 1
        fi
        
        # 检查目录权限
        if [ ! -w "$dir" ]; then
            log_error "目录无写入权限: $dir"
            return 1
        fi
    done
    
    if systemctl is-active --quiet ${APP_NAME}; then
        log_info "应用已在运行"
        return 0
    fi
    
    sudo systemctl start ${APP_NAME}
    
    # 等待服务启动
    local timeout=30
    while [ $timeout -gt 0 ]; do
        if systemctl is-active --quiet ${APP_NAME}; then
            log_info "应用已启动"
            return 0
        fi
        sleep 1
        ((timeout--))
    done
    
    log_error "应用启动超时"
    return 1
}

# 停止应用
stop_application() {
    log_info "停止应用..."
    log_cmd "sudo systemctl stop ${APP_NAME}"
    sudo systemctl stop ${APP_NAME}
}

# 检查应用状态
check_application_status() {
    log_info "检查应用状态..."
    
    # 检查进程
    if ! systemctl is-active --quiet ${APP_NAME}; then
        log_error "服务未运行"
        return 1
    fi
    
    # 检查JAR文件
    if [ ! -f "${INSTALL_DIR}/${APP_NAME}.jar" ]; then
        log_error "JAR文件不存在"
        return 1
    fi
    
    # 检查日志文件
    if [ ! -f "${INSTALL_DIR}/logs/application.log" ]; then
        log_error "日志文件不存在"
        return 1
    fi
    
    # 检查端口
    if ! netstat -tlpn | grep -q ":${APP_PORT}.*java"; then
        log_error "应用端口 ${APP_PORT} 未监听"
        return 1
    fi
    
    log_info "应用运行正常"
    return 0
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
    echo "  update        更新应用最新版本"
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
    echo "1. 应用程文件"
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

# 更新应用
update_application() {
    log_info "开始更新应用..."
    
    # 检查主目录
    if [ ! -d "${INSTALL_DIR}" ]; then
        log_error "安装目录不存在: ${INSTALL_DIR}"
        return 1
    fi
    
    log_cmd "cd ${INSTALL_DIR}/source"
    cd "${INSTALL_DIR}/source"
    
    # 清理旧的构建文件
    log_cmd "rm -rf target/"
    rm -rf target/
    
    # 清理旧的构建日志
    rm -f "${INSTALL_DIR}"/{build.log,maven.log}
    
    log_cmd "git fetch origin"
    git fetch origin
    
    # 获取当前版本
    log_cmd "git rev-parse HEAD"
    local current_version=$(git rev-parse HEAD)
    log_cmd "git rev-parse origin/${GIT_BRANCH}"
    local remote_version=$(git rev-parse origin/${GIT_BRANCH})
    
    if [ "${current_version}" = "${remote_version}" ]; then
        log_info "当前已是最新版本"
        return 0
    fi
    
    # 更新代码
    log_cmd "git pull origin ${GIT_BRANCH}"
    git pull origin ${GIT_BRANCH}
    
    # 构建应用
    if ! build_application; then
        log_error "构建失败，正在回滚..."
        git reset --hard ${current_version}
        return 1
    fi
    
    # 检查构建结果
    if ! check_build_result; then
        log_error "构建检查失败，正在回滚..."
        git reset --hard ${current_version}
        return 1
    fi
    
    # 更新版本信息
    git rev-parse HEAD > ${VERSION_FILE}
    
    # 启动服务
    start_application
    
    # 检查服务状态
    if check_application_status; then
        log_info "更新成功"
        
        # 创建回滚脚本
        create_rollback_script ${current_version} "${BACKUP_DIR}/${APP_NAME}-${current_version}.jar"
        log_info "已创建回滚脚本: ${ROLLBACK_SCRIPT}"
    else
        log_error "更新后服务启动失败，正在回滚..."
        cp "${BACKUP_DIR}/${APP_NAME}-${current_version}.jar" "${INSTALL_DIR}/${APP_NAME}.jar"
        start_application
        return 1
    fi
}

# 克隆代码前添加检查
git_clone() {
    log_info "克隆代码..."
    
    # 检查目标目录
    if [ -d "${INSTALL_DIR}/source" ]; then
        log_info "清理已存在的源码目录..."
        rm -rf "${INSTALL_DIR}/source"
    fi
    
    git clone -b ${GIT_BRANCH} ${GIT_REPO} "${INSTALL_DIR}/source"
}

# 更新应用时的构建检查
check_build_result() {
    local FINAL_JAR="${INSTALL_DIR}/${APP_NAME}.jar"
    local BUILD_LOG="${INSTALL_DIR}/last-build.log"
    local MAVEN_LOG="${INSTALL_DIR}/last-maven.log"
    
    # 检查构建日志中的错误
    if [ -f "${MAVEN_LOG}" ]; then
        if grep -i "BUILD FAILURE" "${MAVEN_LOG}" > /dev/null; then
            log_error "Maven构建失败，详见日志: ${MAVEN_LOG}"
            return 1
        fi
    fi
    
    # 检查最终JAR文件
    if [ ! -f "${FINAL_JAR}" ]; then
        log_error "构建后JAR文件不存在"
        return 1
    fi
    
    # 验证JAR文件
    if ! jar tvf "${FINAL_JAR}" > /dev/null 2>&1; then
        log_error "JAR文件验证失败"
        return 1
    fi
    
    return 0
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