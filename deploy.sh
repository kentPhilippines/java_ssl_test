#!/bin/bash

# 配置变量
APP_NAME="ssl-test-project"
APP_JAR="target/${APP_NAME}-1.0-SNAPSHOT.jar"
APP_USER="$(whoami)"
APP_GROUP="$(id -gn)"
LOG_DIR="/var/log/${APP_NAME}"
PID_FILE="/var/run/${APP_NAME}.pid"
INSTALL_DIR="/opt/${APP_NAME}"
BACKUP_DIR="/opt/${APP_NAME}/backup"
JDK_VERSION="11"

# 添加版本控制相关变量
GIT_REPO="https://github.com/your-org/your-repo.git"
GIT_BRANCH="main"
VERSION_FILE="${INSTALL_DIR}/VERSION"
ROLLBACK_SCRIPT="${INSTALL_DIR}/rollback.sh"

# 添加Maven相关配置
MAVEN_OPTS="-Xmx1024m -XX:MaxPermSize=256m"
MAVEN_ARGS="clean package -DskipTests"
MAVEN_SETTINGS="${HOME}/.m2/settings.xml"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 未安装"
        return 1
    fi
}

# 安装依赖
install_dependencies() {
    log_info "检查并安装依赖..."
    
    # 检查系统类型
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y openjdk-${JDK_VERSION}-jdk maven authbind curl
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        sudo yum update
        sudo yum install -y java-${JDK_VERSION}-openjdk-devel maven curl
    else
        log_error "不支持的操作系统"
        exit 1
    fi
    
    # 验证安装
    check_command java || exit 1
    check_command mvn || exit 1
    check_command curl || exit 1
}

# 配置环境
setup_environment() {
    log_info "配置环境..."
    
    # 创建必要的目录
    sudo mkdir -p ${INSTALL_DIR} ${LOG_DIR} ${BACKUP_DIR}
    sudo chown -R ${APP_USER}:${APP_GROUP} ${INSTALL_DIR} ${LOG_DIR}
    
    # 配置80端口访问权限
    if [ $EUID -ne 0 ]; then
        log_info "配置80端口访问权限..."
        if command -v authbind &> /dev/null; then
            sudo touch /etc/authbind/byport/80
            sudo chmod 500 /etc/authbind/byport/80
            sudo chown ${APP_USER} /etc/authbind/byport/80
        else
            sudo setcap 'cap_net_bind_service=+ep' $(readlink -f /usr/bin/java)
        fi
    fi
    
    # 创建服务文件
    create_service_file
}

# 创建服务文件
create_service_file() {
    log_info "创建系统服务..."
    
    sudo bash -c "cat > /etc/systemd/system/${APP_NAME}.service" << EOF
[Unit]
Description=SSL Test Application
After=network.target

[Service]
User=${APP_USER}
Group=${APP_GROUP}
Environment="KEYSTORE_PASSWORD=${KEYSTORE_PASSWORD}"
Environment="SMTP_USERNAME=${SMTP_USERNAME}"
Environment="SMTP_PASSWORD=${SMTP_PASSWORD}"
Environment="JAVA_OPTS=-Xms512m -Xmx1024m"
ExecStart=/usr/bin/java \$JAVA_OPTS -jar ${INSTALL_DIR}/${APP_NAME}.jar
WorkingDirectory=${INSTALL_DIR}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
}

# 备份当前版本
backup_current_version() {
    if [ -f "${INSTALL_DIR}/${APP_NAME}.jar" ]; then
        local backup_file="${BACKUP_DIR}/${APP_NAME}-$(date +%Y%m%d_%H%M%S).jar"
        log_info "备份当前版本到 ${backup_file}"
        cp "${INSTALL_DIR}/${APP_NAME}.jar" "${backup_file}"
    fi
}

# 停止应用
stop_application() {
    log_info "停止应用..."
    sudo systemctl stop ${APP_NAME} || true
    
    # 确保进程已停止
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE") 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    
    # 等待进程完全停止
    sleep 5
}

# 启动应用
start_application() {
    log_info "启动应用..."
    sudo systemctl start ${APP_NAME}
    sudo systemctl enable ${APP_NAME}
}

# 检查应用状态
check_application_status() {
    log_info "检查应用状态..."
    sleep 10
    
    # 检查HTTP端口
    if curl -s http://localhost:80/.well-known/acme-challenge/test > /dev/null; then
        log_info "HTTP(80)端口检查成功"
    else
        log_error "HTTP端口可能未正确配置"
    fi
    
    # 检查HTTPS端口
    if curl -sk https://localhost:8443/ssl-test > /dev/null; then
        log_info "HTTPS(8443)端口检查成功"
    else
        log_error "HTTPS端口可能未正确配置"
    fi
    
    # 显示服务状态
    sudo systemctl status ${APP_NAME}
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
    
    log_info "清理环境..."
    
    # 停止服务
    stop_application
    
    # 删除服务文件
    sudo rm -f /etc/systemd/system/${APP_NAME}.service
    sudo systemctl daemon-reload
    
    # 删除应用文件
    sudo rm -rf ${INSTALL_DIR}
    sudo rm -rf ${LOG_DIR}
    
    # 清理端口配置
    sudo rm -f /etc/authbind/byport/80
    sudo setcap -r $(readlink -f /usr/bin/java)
    
    log_info "环境清理完成"
}

# 检查并配置Git凭证
setup_git_credentials() {
    log_info "配置Git环境..."
    
    # 检查是否为公开仓库
    if [[ "${GIT_REPO}" == *"github.com"* ]]; then
        # 测试仓库可访问性
        if ! git ls-remote --quiet "${GIT_REPO}" &>/dev/null; then
            log_error "无法访问Git仓库: ${GIT_REPO}"
            echo -e "${YELLOW}可能的原因:${NC}"
            echo "1. 仓库地址错误"
            echo "2. 仓库不存在或已被删除"
            echo "3. 网络连接问题"
            return 1
        fi
        
        log_info "公开仓库验证成功"
        return 0
    fi
}

# 检查并配置Maven设置
setup_maven_settings() {
    log_info "配置Maven环境..."
    
    # 检查Maven settings文件
    if [ ! -f "${MAVEN_SETTINGS}" ]; then
        # 创建基础的settings.xml
        mkdir -p "${HOME}/.m2"
        cat > "${MAVEN_SETTINGS}" << EOF
<settings>
    <mirrors>
        <mirror>
            <id>aliyun</id>
            <name>Aliyun Maven Mirror</name>
            <url>https://maven.aliyun.com/repository/public</url>
            <mirrorOf>central</mirrorOf>
        </mirror>
    </mirrors>
</settings>
EOF
    fi
    
    # 设置Maven环境变量
    export MAVEN_OPTS
}

# 改进代码更新检查
check_code_updates() {
    log_info "检查代码更新..."
    
    # 验证仓库访问
    setup_git_credentials || return 1
    
    local clone_failed=0
    local pull_failed=0
    
    # 如果目录不存在，执行克隆
    if [ ! -d "${INSTALL_DIR}/source" ]; then
        log_info "克隆代码库: ${GIT_REPO} (分支: ${GIT_BRANCH})"
        if ! git clone -b ${GIT_BRANCH} ${GIT_REPO} "${INSTALL_DIR}/source"; then
            log_error "代码克隆失败"
            clone_failed=1
        fi
        cd "${INSTALL_DIR}/source"
    else
        cd "${INSTALL_DIR}/source"
        
        # 检查远程仓库URL是否正确
        local current_url=$(git config --get remote.origin.url)
        if [ "${current_url}" != "${GIT_REPO}" ]; then
            log_info "更新远程仓库地址..."
            git remote set-url origin "${GIT_REPO}"
        fi
        
        # 检查并清理本地修改
        if [ -n "$(git status --porcelain)" ]; then
            log_info "检测到本地修改，正在重置..."
            git reset --hard
            git clean -fd
        fi
        
        # 获取远程更新
        if ! git fetch origin ${GIT_BRANCH}; then
            log_error "获取远程更新失败"
            pull_failed=1
        fi
        
        # 检查是否有更新
        if [ $pull_failed -eq 0 ]; then
            LOCAL_COMMIT=$(git rev-parse HEAD)
            REMOTE_COMMIT=$(git rev-parse origin/${GIT_BRANCH})
            
            if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ]; then
                log_info "代码已是最新版本 (${LOCAL_COMMIT:0:7})"
                return 1
            fi
            
            log_info "发现新版本: ${REMOTE_COMMIT:0:7}"
            # 更新代码
            if ! git pull origin ${GIT_BRANCH}; then
                log_error "代码更新失败"
                pull_failed=1
            fi
        fi
    fi
    
    # 如果发生错误，给出具体提示
    if [ $clone_failed -eq 1 ] || [ $pull_failed -eq 1 ]; then
        echo -e "${YELLOW}可能的原因:${NC}"
        echo "1. 仓库地址错误: ${GIT_REPO}"
        echo "2. 分支名称错误: ${GIT_BRANCH}"
        echo "3. 网络连接问题"
        echo
        echo -e "${YELLOW}建议操作:${NC}"
        echo "1. 验证仓库地址和分支名称"
        echo "2. 检查网络连接"
        echo "3. 尝试手动克隆仓库"
        return 1
    fi
    
    # 保存版本信息
    git rev-parse HEAD > ${VERSION_FILE}
    log_info "代码已更新到: $(git rev-parse --short HEAD)"
    return 0
}

# 改进Maven构建
build_application() {
    log_info "开始构建应用..."
    
    # 配置Maven环境
    setup_maven_settings
    
    # 清理之前的构建
    if [ -d "target" ]; then
        log_info "清理之前的构建..."
        rm -rf target/
    fi
    
    # 执行构建
    log_info "执行Maven构建..."
    if ! mvn ${MAVEN_ARGS}; then
        echo -e "${YELLOW}构建失败可能的原因:${NC}"
        echo "1. Maven配置问题"
        echo "2. 依赖下载失败"
        echo "3. 编译错误"
        echo "4. 测试失败"
        echo
        echo -e "${YELLOW}建议操作:${NC}"
        echo "1. 检查 ${MAVEN_SETTINGS} 配置"
        echo "2. 检查网络连接"
        echo "3. 查看详细错误日志"
        echo "4. 尝试手动执行: mvn ${MAVEN_ARGS}"
        return 1
    fi
    
    # 检查构建结果
    if [ ! -f "target/${APP_NAME}-1.0-SNAPSHOT.jar" ]; then
        log_error "构建完成但未找到目标JAR文件"
        return 1
    fi
    
    log_info "构建成功"
    return 0
}

# 修改更新应用函数
update_application() {
    log_info "准备更新应用..."
    echo -e "${YELLOW}更新步骤:${NC}"
    echo "1. 检查代码更新"
    echo "2. 备份当���版本"
    echo "3. 构建新版本"
    echo "4. 部署并重启服务"
    echo
    
    if [ -f "${VERSION_FILE}" ]; then
        echo -e "${YELLOW}当前版本信息:${NC}"
        version_info
        echo
    fi
    
    read -p "是否继续更新? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    
    # 检查代码更新
    if check_code_updates; then
        local current_version=$(cat ${VERSION_FILE} 2>/dev/null || echo "initial")
        
        # 备份当前版本
        if [ -f "${INSTALL_DIR}/${APP_NAME}.jar" ]; then
            local backup_file="${BACKUP_DIR}/${APP_NAME}-${current_version}.jar"
            backup_current_version "${backup_file}"
            create_rollback_script "${current_version}" "${backup_file}"
        fi
        
        # 构建新版本
        cd "${INSTALL_DIR}/source"
        if ! build_application; then
            log_error "构建失败，取消更新"
            return 1
        fi
        
        # 部署新版本
        stop_application
        cp "target/${APP_NAME}-1.0-SNAPSHOT.jar" "${INSTALL_DIR}/${APP_NAME}.jar"
        start_application
        
        # 检查状态
        if ! check_application_status; then
            log_error "新版本启动失败，准备回滚..."
            ${ROLLBACK_SCRIPT}
            return 1
        fi
        
        log_info "更新成功，新版本: $(git rev-parse --short HEAD)"
    fi
}

# 添加版本管理相关命令
version_info() {
    if [ -f "${VERSION_FILE}" ]; then
        local version=$(cat ${VERSION_FILE})
        cd "${INSTALL_DIR}/source"
        log_info "当前版本: $(git rev-parse --short ${version})"
        log_info "部署时间: $(stat -c %y ${INSTALL_DIR}/${APP_NAME}.jar)"
        log_info "提交信息: $(git log -1 --pretty=format:'%s' ${version})"
    else
        log_error "未找到版本信息"
    fi
}

# 添加回滚命令
rollback() {
    local version=$1
    if [ -z "$version" ]; then
        log_error "请指定要回滚的版本"
        echo -e "${YELLOW}可用版本:${NC}"
        cd "${INSTALL_DIR}/source"
        git log --oneline -n 5
        return 1
    fi
    
    echo -e "${YELLOW}回滚信息:${NC}"
    echo "目标版本: $version"
    echo -e "版本描述: $(git log -1 --pretty=format:'%s' $version 2>/dev/null || echo '未知版本')"
    echo
    
    read -p "确认回滚到此版本? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    
    cd "${INSTALL_DIR}/source"
    if ! git rev-parse --verify ${version} >/dev/null 2>&1; then
        log_error "无效的版本: ${version}"
        return 1
    fi
    
    # 查找对应的备份文件
    local backup_file="${BACKUP_DIR}/${APP_NAME}-${version}.jar"
    if [ ! -f "${backup_file}" ]; then
        log_error "未找到版本 ${version} 的备份文件"
        return 1
    fi
    
    # 执行回滚
    stop_application
    cp "${backup_file}" "${INSTALL_DIR}/${APP_NAME}.jar"
    git reset --hard ${version}
    echo ${version} > ${VERSION_FILE}
    start_application
    
    log_info "已回滚到版本 ${version}"
}

# 添加帮助函数
show_help() {
    echo -e "${BLUE}SSL测试项目部署脚本${NC}"
    echo
    echo -e "${YELLOW}用法:${NC}"
    echo "  $0 <命令> [参数]"
    echo
    echo -e "${YELLOW}可用命令:${NC}"
    echo -e "  ${GREEN}install${NC}        首次安装应用"
    echo -e "  ${GREEN}update${NC}         更新应用到最新版本"
    echo -e "  ${GREEN}start${NC}          启动应用"
    echo -e "  ${GREEN}stop${NC}           停止应用"
    echo -e "  ${GREEN}restart${NC}        重启应用"
    echo -e "  ${GREEN}status${NC}         查看应用状态"
    echo -e "  ${GREEN}version${NC}        显示当前版本信息"
    echo -e "  ${GREEN}rollback${NC} <版本> 回滚到指定版本"
    echo -e "  ${GREEN}cleanup${NC}        清理环境"
    echo -e "  ${GREEN}help${NC}           显示此帮助信息"
    echo
    echo -e "${YELLOW}示例:${NC}"
    echo "  $0 install              # 首次安装应用"
    echo "  $0 update              # 更新到最新版本"
    echo "  $0 rollback abc123f    # 回滚到指定版本"
    echo
    echo -e "${YELLOW}环境要求:${NC}"
    echo "  - JDK ${JDK_VERSION}"
    echo "  - Maven"
    echo "  - Git"
    echo "  - 系统权限配置（用于80端口）"
    echo
    echo -e "${YELLOW}注意事项:${NC}"
    echo "  1. 首次运行需要root权限配置80端口"
    echo "  2. 确保已正确配置Git仓库地址"
    echo "  3. 更新前会自动备份当前版本"
    echo "  4. 回滚操作需要指定具体的提交哈希"
    echo
    echo -e "${YELLOW}配置说明:${NC}"
    echo "  1. 设置正确的Git仓库地址:"
    echo "     - 编辑脚本开头的 GIT_REPO 变量"
    echo "     - 例如: GIT_REPO=\"https://github.com/your-org/your-repo.git\""
    echo "  2. 设置正确的分支名称:"
    echo "     - 编辑脚本开头的 GIT_BRANCH 变量"
    echo "     - 默认为 \"main\""
}

# 在每个主要操作前添加操作提示
install_application() {
    log_info "开始安装应用..."
    echo -e "${YELLOW}安装步骤:${NC}"
    echo "1. 安装必要的依赖"
    echo "2. 配置运行环境"
    echo "3. 下载并构建代码"
    echo "4. 配置系统服务"
    echo "5. 启动应用"
    echo
    
    read -p "是否继续安装? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    
    install_dependencies
    setup_environment
    update_application
}

# 修改主函数，添加帮助命令
main() {
    case "$1" in
        install)
            install_application
            ;;
        help|--help|-h)
            show_help
            ;;
        update)
            update_application
            ;;
        version)
            version_info
            ;;
        rollback)
            rollback "$2"
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