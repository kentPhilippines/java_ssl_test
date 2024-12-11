package com.ssltest.model;

import lombok.Data;
import lombok.Builder;

@Data
@Builder
public class CertificateResult {
    private String certificatePem;  // PEM格式的证书
    private String privateKeyPem;   // PEM格式的私钥
    private String domain;          // 域名
    private long expirationTime;    // 过期时间
} 