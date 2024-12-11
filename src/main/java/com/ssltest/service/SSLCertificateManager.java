package com.ssltest.service;

import lombok.extern.slf4j.Slf4j;
import org.apache.catalina.connector.Connector;
import org.apache.tomcat.util.net.SSLHostConfig;
import org.apache.tomcat.util.net.SSLHostConfigCertificate;
import org.apache.tomcat.util.net.SSLHostConfigCertificate.Type;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.web.embedded.tomcat.TomcatServletWebServerFactory;
import org.springframework.boot.web.embedded.tomcat.TomcatWebServer;
import org.springframework.boot.web.servlet.context.ServletWebServerApplicationContext;
import org.springframework.stereotype.Service;
import org.springframework.beans.factory.annotation.Value;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.*;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.Base64;
import java.nio.file.attribute.PosixFilePermissions;

@Slf4j
@Service
public class SSLCertificateManager {

    @Autowired
    private ServletWebServerApplicationContext webServerAppCtx;

    @Value("${server.port:8443}")
    private int httpsPort;

    @Value("${server.ssl.protocol:TLS}")
    private String sslProtocol;

    public void updateCertificate(String certificatePem, String privateKeyPem) throws Exception {
        validateCertificateAndKey(certificatePem, privateKeyPem);
        
        Path certFile = null;
        Path keyFile = null;
        
        try {
            certFile = createTempFile("cert_", ".pem", certificatePem);
            keyFile = createTempFile("key_", ".pem", privateKeyPem);
            
            configureSslConnector(certFile, keyFile);
            log.info("SSL证书更新成功");
            
        } catch (Exception e) {
            log.error("更新SSL证书失败: {}", e.getMessage(), e);
            throw new RuntimeException("证书更新失败: " + e.getMessage(), e);
        } finally {
            secureDelete(certFile);
            secureDelete(keyFile);
        }
    }

    private Path createTempFile(String prefix, String suffix, String content) throws IOException {
        Path file = Files.createTempFile(prefix, suffix);
        Files.write(file, content.getBytes());
        Files.setPosixFilePermissions(file, PosixFilePermissions.fromString("rw-------"));
        return file;
    }

    private void validateCertificateAndKey(String cert, String key) {
        if (!cert.contains("BEGIN CERTIFICATE") || !key.contains("BEGIN PRIVATE KEY")) {
            throw new IllegalArgumentException("无效的证书或私钥格式");
        }
    }

    private void configureSslConnector(Path certFile, Path keyFile) throws Exception {
        TomcatWebServer tomcatWebServer = (TomcatWebServer) webServerAppCtx.getWebServer();
        org.apache.catalina.Service service = tomcatWebServer.getTomcat().getService();
        
        // 停止现有的HTTPS连接器
        for (Connector connector : service.findConnectors()) {
            if (connector.getScheme().equals("https")) {
                connector.stop();
                service.removeConnector(connector);
            }
        }
        
        // 创建新的HTTPS连接器
        Connector httpsConnector = new Connector(TomcatServletWebServerFactory.DEFAULT_PROTOCOL);
        httpsConnector.setPort(httpsPort);
        httpsConnector.setSecure(true);
        httpsConnector.setScheme("https");
        
        SSLHostConfig sslHostConfig = new SSLHostConfig();
        SSLHostConfigCertificate cert = new SSLHostConfigCertificate(sslHostConfig, Type.RSA);
        cert.setCertificateFile(certFile.toString());
        cert.setCertificateKeyFile(keyFile.toString());
        
        // 配置SSL参数
        sslHostConfig.setProtocols(sslProtocol);
        sslHostConfig.setCiphers("TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384");
        
        sslHostConfig.addCertificate(cert);
        httpsConnector.addSslHostConfig(sslHostConfig);
        
        // 添加并启动新连接器
        service.addConnector(httpsConnector);
        httpsConnector.start();
    }

    private void secureDelete(Path file) {
        try {
            // 覆盖文件内容
            RandomAccessFile raf = new RandomAccessFile(file.toFile(), "rws");
            long length = raf.length();
            raf.seek(0);
            raf.write(new byte[(int)length]);
            raf.close();
            
            // 删除文件
            Files.deleteIfExists(file);
        } catch (Exception e) {
            log.warn("清理临时文件失败: {}", file, e);
        }
    }
} 