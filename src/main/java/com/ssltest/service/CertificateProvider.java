package com.ssltest.service;

public interface CertificateProvider {
    /**
     * 申请SSL证书
     * @param domain 域名
     * @return 包含证书和私钥的对象
     */
    CertificateResult applyCertificate(String domain) throws Exception;
} 