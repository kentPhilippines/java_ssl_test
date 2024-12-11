package com.ssltest.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.*;
import java.security.*;
import java.security.cert.X509Certificate;

@Slf4j
@Service
public class KeyStoreService {
    
    @Value("${acme.security.key-store-type:PKCS12}")
    private String keyStoreType;
    
    @Value("${acme.security.key-store-password:changeit}")
    private String keyStorePassword;
    
    @Value("${acme.security.key-store:${user.home}/.acme/keystore.p12}")
    private String keyStore;
    
    @Value("${acme.security.allow-http:true}")
    private boolean allowHttp;
    
    public void saveKeyPair(String alias, PrivateKey privateKey, X509Certificate cert) throws Exception {
        KeyStore keyStore = getOrCreateKeyStore();
        keyStore.setKeyEntry(alias, privateKey, keyStorePassword.toCharArray(), 
                new X509Certificate[]{cert});
        
        try (FileOutputStream fos = new FileOutputStream(keyStore)) {
            keyStore.store(fos, keyStorePassword.toCharArray());
        }
    }
    
    private KeyStore getOrCreateKeyStore() throws Exception {
        KeyStore keyStore = KeyStore.getInstance(keyStoreType);
        File keyStoreFile = new File(keyStore);
        
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