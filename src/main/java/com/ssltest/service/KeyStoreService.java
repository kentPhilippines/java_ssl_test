package com.ssltest.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileWriter;
import java.security.KeyStore;
import java.security.KeyStore.PasswordProtection;
import java.security.KeyStore.ProtectionParameter;
import java.security.KeyStore.SecretKeyEntry;
import java.security.KeyStore.TrustedCertificateEntry;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.Enumeration;

import javax.annotation.PostConstruct;

@Service
public class KeyStoreService {
    
    @Value("${acme.security.key-store-type:PKCS12}")
    private String keyStoreType;
    
    @Value("${acme.security.key-store-password:changeit}")
    private String keyStorePassword;
    
    @Value("${acme.storage.path:${user.dir}/data/ssl}")
    private String storagePath;
    
    private String keyStorePath;
    
    @PostConstruct
    public void init() {
        keyStorePath = new File(storagePath, "keystore.p12").getAbsolutePath();
        File keyStoreDir = new File(storagePath);
        if (!keyStoreDir.exists() && !keyStoreDir.mkdirs()) {
            throw new RuntimeException("无法创建KeyStore目录: " + storagePath);
        }
        log.info("KeyStore配置初始化完成:");
        log.info("KeyStore类型: {}", keyStoreType);
        log.info("KeyStore路径: {}", keyStorePath);
    }
    
    private KeyStore getOrCreateKeyStore() throws Exception {
        KeyStore keyStore = KeyStore.getInstance(keyStoreType);
        File keyStoreFile = new File(keyStorePath);
        
        if (keyStoreFile.exists()) {
            try (FileInputStream fis = new FileInputStream(keyStoreFile)) {
                keyStore.load(fis, keyStorePassword.toCharArray());
            }
        } else {
            keyStore.load(null, null);
            keyStoreFile.getParentFile().mkdirs();
        }
        
        return keyStore;
    }
} 