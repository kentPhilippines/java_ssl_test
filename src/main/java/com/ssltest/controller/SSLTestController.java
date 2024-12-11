package com.ssltest.controller;

import com.ssltest.model.CertificateResult;
import com.ssltest.service.CertificateProvider;
import com.ssltest.service.SSLCertificateManager;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.web.bind.annotation.*;

@Slf4j
@RestController
public class SSLTestController {

    @Autowired
    private SSLCertificateManager sslManager;
    
    @Autowired
    @Qualifier("retryableAcmeCertificateProvider")
    private CertificateProvider certificateProvider;

    @GetMapping("/ssl-test")
    public String testSSL() {
        return "SSL连接测试成功！";
    }

    @PostMapping("/api/ssl/apply")
    public String applyCertificate(@RequestParam String domain) {
        try {
            // 申请证书
            CertificateResult result = certificateProvider.applyCertificate(domain);
            
            // 更新SSL配置
            sslManager.updateCertificate(result.getCertificatePem(), result.getPrivateKeyPem());
            
            return String.format("证书申请成功，域名: %s, 过期时间: %s", 
                    result.getDomain(), 
                    new java.util.Date(result.getExpirationTime()));
        } catch (Exception e) {
            log.error("证书申请失败", e);
            return "证书申请失败: " + e.getMessage();
        }
    }
} 