package com.ssltest.model;

import lombok.Data;

@Data
public class CertificateUpdateRequest {
    private String domain;          // 域名
    private String certificateStr;  // PEM格式的证书字符串
    private String privateKeyStr;   // PEM格式的私钥字符串
} 