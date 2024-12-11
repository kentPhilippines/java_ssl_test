# 使用多阶段构建
FROM maven:3.9.6-eclipse-temurin-17 AS builder

# 设置工作目录
WORKDIR /build

# 配置Maven镜像
RUN mkdir -p /root/.m2 \
    && echo '<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0" \
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" \
      xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 \
      https://maven.apache.org/xsd/settings-1.0.0.xsd"> \
      <mirrors> \
        <mirror> \
          <id>aliyun</id> \
          <name>Aliyun Maven Mirror</name> \
          <url>https://maven.aliyun.com/repository/public</url> \
          <mirrorOf>central</mirrorOf> \
        </mirror> \
      </mirrors> \
    </settings>' > /root/.m2/settings.xml

# 复制 pom.xml
COPY pom.xml .

# 下载依赖
RUN mvn dependency:go-offline -DskipTests

# 复制源代码
COPY src ./src

# 构建应用
RUN mvn clean package -DskipTests

# 运行阶段使用更小的基础镜像
FROM eclipse-temurin:17-jre-jammy

# 安装必要的工具
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 创建必要的目录结构
RUN mkdir -p \
    /app/data/ssl/keys \
    /app/data/ssl/certs \
    /app/data/acme \
    /app/data/db \
    /app/logs \
    /app/conf

# 复制构建产物
COPY --from=builder /build/target/*.jar app.jar

# 创建默认配置文件
RUN echo "server:\n\
  port: 8443\n\
  http:\n\
    port: 80\n\
  ssl:\n\
    enabled: true\n\
    key-store: /app/data/ssl/keystore.p12\n\
    key-store-password: changeit\n\
    key-store-type: PKCS12\n\
\n\
spring:\n\
  application:\n\
    name: ssl-test\n\
  profiles:\n\
    active: prod\n\
  datasource:\n\
    url: jdbc:h2:file:/app/data/db/ssl\n\
    username: sa\n\
    password: password\n\
    driver-class-name: org.h2.Driver\n\
\n\
logging:\n\
  file:\n\
    path: /app/logs\n\
  level:\n\
    root: INFO\n\
    com.ssltest: DEBUG\n\
\n\
acme:\n\
  server:\n\
    url: ${ACME_SERVER_URL:-https://acme-staging-v02.api.letsencrypt.org/directory}\n\
  account:\n\
    email: ${ACME_EMAIL:-admin@example.com}\n\
  security:\n\
    key-store-type: PKCS12\n\
    key-store-password: changeit\n\
    allow-http: true\n\
    key-store: /app/data/ssl/keystore.p12\n\
  storage:\n\
    path: /app/data/ssl\n\
  client:\n\
    renewal-days: 30\n\
    notify-days: 7\n\
    auto-renewal: true\n\
    ocsp-check-hours: 24\n\
  challenge:\n\
    type: HTTP-01\n\
    http-port: 80\n\
    timeout: 180\n\
    retries: 3\n\
    retry-interval: 10" > /app/conf/application.yml

# 设置权限
RUN chmod -R 755 /app \
    && chmod 700 /app/data/ssl/keys \
    && chmod 700 /app/data/ssl/certs \
    && chmod 700 /app/data/acme \
    && chmod 700 /app/data/db

# 设置环境变量
ENV JAVA_OPTS="-Xmx512m -Xms256m" \
    APP_PORT=8443 \
    HTTP_PORT=80 \
    SPRING_CONFIG_LOCATION=/app/conf/application.yml

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:$HTTP_PORT/actuator/health || exit 1

# 暴露端口
EXPOSE $APP_PORT $HTTP_PORT

# 启动命令
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"] 