package com.ssltest.service;

import lombok.extern.slf4j.Slf4j;
import org.apache.catalina.connector.Connector;
import org.apache.tomcat.util.net.SSLHostConfig;
import org.apache.tomcat.util.net.SSLHostConfigCertificate;
import org.apache.tomcat.util.net.SSLHostConfigCertificate.Type;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.web.embedded.tomcat.TomcatWebServer;
import org.springframework.boot.web.servlet.context.ServletWebServerApplicationContext;
import org.springframework.stereotype.Service;

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

    public void updateCertificate(String certificatePem, String privateKeyPem) throws Exception {
        // 验证证书内容
        if (!certificatePem.contains("BEGIN CERTIFICATE") || !privateKeyPem.contains("BEGIN PRIVATE KEY")) {
            throw new IllegalArgumentException("无效的证书或私钥格式");
        }
        
        Path certFile = null;
        Path keyFile = null;
        
        try {
            // 保存证书和私钥到临时文件
            certFile = Files.createTempFile("cert_", ".pem");
            keyFile = Files.createTempFile("key_", ".pem");
            
            Files.write(certFile, certificatePem.getBytes());
            Files.write(keyFile, privateKeyPem.getBytes());
            
            // 设置文件权限
            Files.setPosixFilePermissions(certFile, PosixFilePermissions.fromString("rw-------"));
            Files.setPosixFilePermissions(keyFile, PosixFilePermissions.fromString("rw-------"));
            
            // 配置HTTPS连接器
            configureSslConnector(certFile, keyFile);
            
        } catch (Exception e) {
            log.error("更新SSL证书失败", e);
            throw new RuntimeException("证书更新失败: " + e.getMessage());
        } finally {
            // 安全清理临时文件
            if (certFile != null) {
                secureDelete(certFile);
            }
            if (keyFile != null) {
                secureDelete(keyFile);
            }
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
        httpsConnector.setPort(8443);
        httpsConnector.setSecure(true);
        httpsConnector.setScheme("https");
        
        SSLHostConfig sslHostConfig = new SSLHostConfig();
        SSLHostConfigCertificate cert = new SSLHostConfigCertificate(sslHostConfig, Type.RSA);
        cert.setCertificateFile(certFile.toString());
        cert.setCertificateKeyFile(keyFile.toString());
        
        // 配置SSL参数
        sslHostConfig.setProtocols("TLSv1.2,TLSv1.3");
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

    private X509Certificate convertPemToCertificate(String certificatePem) throws Exception {
        // 移除PEM头尾和换行符
        String cleanCert = certificatePem
                .replace("-----BEGIN CERTIFICATE-----", "")
                .replace("-----END CERTIFICATE-----", "")
                .replaceAll("\\s", "");
        
        byte[] certBytes = Base64.getDecoder().decode(cleanCert);
        CertificateFactory cf = CertificateFactory.getInstance("X.509");
        return (X509Certificate) cf.generateCertificate(new ByteArrayInputStream(certBytes));
    }

    private PrivateKey convertPemToPrivateKey(String privateKeyPem) throws Exception {
        // 移除PEM头尾和换行符
        String cleanKey = privateKeyPem
                .replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replaceAll("\\s", "");
        
        byte[] keyBytes = Base64.getDecoder().decode(cleanKey);
        PKCS8EncodedKeySpec spec = new PKCS8EncodedKeySpec(keyBytes);
        KeyFactory kf = KeyFactory.getInstance("RSA");
        return kf.generatePrivate(spec);
    }

    private void saveToKeyStore(X509Certificate cert, PrivateKey privateKey) throws Exception {
        File keystoreFile = new File(KEYSTORE_PATH);
        if (!keystoreFile.getParentFile().exists()) {
            keystoreFile.getParentFile().mkdirs();
        }

        KeyStore keyStore = KeyStore.getInstance("JKS");
        keyStore.load(null, null);
        keyStore.setKeyEntry("tomcat", privateKey, KEYSTORE_PASSWORD.toCharArray(),
                new X509Certificate[]{cert});
        
        try (FileOutputStream fos = new FileOutputStream(keystoreFile)) {
            keyStore.store(fos, KEYSTORE_PASSWORD.toCharArray());
        }
    }

    private void updateHttpsConnector() throws Exception {
        TomcatWebServer tomcatWebServer = (TomcatWebServer) server.getWebServer();
        org.apache.catalina.Service service = tomcatWebServer.getTomcat().getService();

        // 查找或创建HTTPS连接器
        Connector httpsConnector = null;
        for (Connector connector : service.findConnectors()) {
            if (connector.getSecure() && connector.getPort() == HTTPS_PORT) {
                httpsConnector = connector;
                break;
            }
        }

        if (httpsConnector == null) {
            // 创建新的HTTPS连接器
            httpsConnector = new Connector(TomcatWebServer.DEFAULT_PROTOCOL);
            httpsConnector.setPort(HTTPS_PORT);
            httpsConnector.setSecure(true);
            httpsConnector.setScheme("https");
            
            // 配置SSL
            httpsConnector.addProperty("SSLEnabled", "true");
            httpsConnector.addProperty("keystoreFile", KEYSTORE_PATH);
            httpsConnector.addProperty("keystorePass", KEYSTORE_PASSWORD);
            httpsConnector.addProperty("keyAlias", "tomcat");
            httpsConnector.addProperty("clientAuth", "false");
            
            service.addConnector(httpsConnector);
        }

        // 重启连接器以应用新的SSL配置
        httpsConnector.stop();
        httpsConnector.start();
    }
} 