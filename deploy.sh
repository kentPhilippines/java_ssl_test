#!/bin/bash

# 基础配置
APP_NAME="ssl-test-project"
WORK_DIR="$(pwd)"
SOURCE_DIR="${WORK_DIR}/source"
DOCKER_COMPOSE="docker-compose"
DOCKER_IMAGE="ssl-service"
GIT_REPO="https://github.com/kentPhilippines/java_ssl_test.git"
GIT_BRANCH="main"

# ACME配置
ACME_EMAIL="${ACME_EMAIL:-admin@example.com}"
ACME_STAGING="${ACME_STAGING:-true}"
ACME_SERVER_URL="https://acme-staging-v02.api.letsencrypt.org/directory"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 检查Docker环境
check_docker() {
    log_info "检查Docker环境..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装"
        return 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose未安装"
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker服务未启动或当前用户无权限"
        return 1
    fi
    
    return 0
}

# 检查Git环境
check_git() {
    log_info "检查Git环境..."
    if ! command -v git &> /dev/null; then
        log_error "Git未安装"
        return 1
    fi
    return 0
}

# 克隆或更新源码
fetch_source() {
    log_info "获取源代码..."
    
    if [ ! -d "${SOURCE_DIR}" ]; then
        log_info "克隆代码库..."
        if ! git clone -b ${GIT_BRANCH} ${GIT_REPO} "${SOURCE_DIR}"; then
            log_error "代码克隆失败"
            return 1
        fi
    else
        log_info "更新代码库..."
        cd "${SOURCE_DIR}"
        git fetch origin
        git reset --hard origin/${GIT_BRANCH}
        if [ $? -ne 0 ]; then
            log_error "代码更新失败"
            return 1
        fi
    fi
    
    # 复制Docker相关文件到源码目录
    cp "${WORK_DIR}/Dockerfile" "${SOURCE_DIR}/"
    cp "${WORK_DIR}/docker-compose.yml" "${SOURCE_DIR}/"
    
    cd "${SOURCE_DIR}"
    return 0
}

# Docker相关函数
docker_build() {
    log_info "构建Docker镜像..."
    cd "${SOURCE_DIR}"
    if ! $DOCKER_COMPOSE build --no-cache; then
        log_error "Docker镜像构建失败"
        return 1
    fi
}

docker_start() {
    log_info "启动Docker容器..."
    cd "${SOURCE_DIR}"
    if ! $DOCKER_COMPOSE up -d; then
        log_error "Docker容器启动失败"
        return 1
    fi
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 10
    
    # 检查服务状态
    if ! curl -sf http://localhost/actuator/health &> /dev/null; then
        log_error "服务启动失败"
        docker_logs
        return 1
    fi
    
    log_info "服务已成功启动"
}

docker_stop() {
    log_info "停止Docker容器..."
    cd "${SOURCE_DIR}"
    $DOCKER_COMPOSE down
}

docker_logs() {
    cd "${SOURCE_DIR}"
    $DOCKER_COMPOSE logs -f
}

docker_status() {
    cd "${SOURCE_DIR}"
    $DOCKER_COMPOSE ps
}

docker_cleanup() {
    log_info "清理Docker资源..."
    cd "${SOURCE_DIR}"
    docker_stop
    docker system prune -f
    docker volume rm $(docker volume ls -q | grep "^ssl-") 2>/dev/null || true
    
    # 清理源码
    cd "${WORK_DIR}"
    if [ -d "${SOURCE_DIR}" ]; then
        log_info "清理源码目录..."
        rm -rf "${SOURCE_DIR}"
    fi
}

# 一键部署函数
deploy() {
    log_info "开始一键部署..."
    
    # 检查环境
    if ! check_git; then
        return 1
    fi
    
    if ! check_docker; then
        return 1
    fi
    
    # 获取源码
    if ! fetch_source; then
        return 1
    fi
    
    # 构建并启动
    if ! docker_build; then
        return 1
    fi
    
    if ! docker_start; then
        return 1
    fi
    
    log_info "部署完成!"
    docker_status
}

# 显示帮助信息
show_help() {
    echo "使用方法: $0 [命令]"
    echo
    echo "可用命令:"
    echo "  install    - 构建并启动服务"
    echo "  start      - 启动服务"
    echo "  stop       - 停止服务"
    echo "  restart    - 重启服务"
    echo "  status     - 查看服务状态"
    echo "  logs       - 查看服务日志"
    echo "  cleanup    - 清理所有资源"
    echo "  update     - 更新服务"
    echo
}

# 主函数
main() {
    case "$1" in
        install)
            deploy
            ;;
        update)
            fetch_source && docker_build && docker_stop && docker_start
            ;;
        start)
            docker_start
            ;;
        stop)
            docker_stop
            ;;
        restart)
            docker_stop && docker_start
            ;;
        status)
            docker_status
            ;;
        logs)
            docker_logs
            ;;
        cleanup)
            docker_cleanup
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