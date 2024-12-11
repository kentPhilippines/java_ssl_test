package com.ssltest.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.File;
import java.io.FileInputStream;
import java.security.KeyStore;

import javax.annotation.PostConstruct;

@Service
@Slf4j
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