package com.ssltest.service.impl;

import com.ssltest.entity.CertificateEntity;
import com.ssltest.model.CertificateResult;
import com.ssltest.repository.CertificateRepository;
import com.ssltest.service.CertificateProvider;
import com.ssltest.service.ChallengeService;
import com.ssltest.service.KeyStoreService;
import lombok.extern.slf4j.Slf4j;
import org.shredzone.acme4j.*;
import org.shredzone.acme4j.challenge.Http01Challenge;
import org.shredzone.acme4j.util.CSRBuilder;
import org.shredzone.acme4j.util.KeyPairUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.io.*;
import java.security.KeyPair;
import java.time.LocalDateTime;
import java.util.List;

@Slf4j
@Service
public class AcmeCertificateProvider implements CertificateProvider {
    
    @Value("${acme.server.url}")
    private String acmeServerUrl;
    
    @Value("${acme.account.email}")
    private String accountEmail;
    
    @Value("${acme.challenge.path}")
    private String challengePath;
    
    @Autowired
    private CertificateRepository certificateRepository;

    
    @Autowired
    private KeyStoreService keyStoreService;
    
    @Autowired
    private ChallengeService challengeService;
    
    private static final String ACCOUNT_KEY_FILE = "ssl/account.key";
    private static final String DOMAIN_KEY_FILE = "ssl/domain.key";

    @Override
    public CertificateResult applyCertificate(String domain) throws Exception {
        log.info("开始为域名{}申请证书", domain);
        
        // 检查是否已有有效证书
        CertificateEntity existingCert = certificateRepository.findByDomain(domain);
        if (existingCert != null && existingCert.getExpiresAt().isAfter(LocalDateTime.now())) {
            log.info("域名{}已有有效证书", domain);
            return convertToResult(existingCert);
        }
        
        try {
            // 获取或创建ACME账户
            Session session = new Session(acmeServerUrl);
            Account account = getOrCreateAccount(session);
            
            // 生成域名密钥对
            KeyPair domainKeyPair = generateOrLoadDomainKeyPair();
            
            // 开始订单流程
            Order order = account.newOrder().domains(domain).create();
            
            // 处理域名验证
            for (Authorization auth : order.getAuthorizations()) {
                processAuthorization(auth);
            }
            
            // 生成CSR并成订单
            CSRBuilder csrb = new CSRBuilder();
            csrb.addDomain(domain);
            csrb.sign(domainKeyPair);
            
            order.execute(csrb.getEncoded());
            Certificate certificate = order.getCertificate();
            
            // 保存证书信息
            CertificateEntity certEntity = new CertificateEntity();
            certEntity.setDomain(domain);
            certEntity.setCertificatePem(certificate.getCertificate());
            certEntity.setPrivateKeyPem(KeyPairUtils.writePrivateKey(domainKeyPair.getPrivate()));
            certEntity.setIssuedAt(LocalDateTime.now());
            certEntity.setExpiresAt(LocalDateTime.now().plusDays(90));
            certEntity.setStatus("ACTIVE");
            certEntity.setAcmeAccountUrl(account.getLocation().toString());
            
            certificateRepository.save(certEntity);
            
            return convertToResult(certEntity);
            
        } catch (Exception e) {
            log.error("证书申请失败: {}", e.getMessage(), e);
            throw new RuntimeException("证书申请失败", e);
        }
    }
    
    @Scheduled(cron = "0 0 0 * * ?") // 每天凌晨执行
    public void renewCertificates() {
        log.info("开始检查证书续期");
        try {
            LocalDateTime renewalDate = LocalDateTime.now().plusDays(30);
            List<CertificateEntity> certificates = certificateRepository
                    .findByExpiresAtBeforeAndStatus(renewalDate, "ACTIVE");
            
            for (CertificateEntity cert : certificates) {
                try {
                    applyCertificate(cert.getDomain());
                    log.info("证书续期成功: {}", cert.getDomain());
                } catch (Exception e) {
                    String message = String.format("域名 %s 的证书续期失败: %s", 
                            cert.getDomain(), e.getMessage());
                    log.error(message, e);
                }
            }
        } catch (Exception e) {
            log.error("证书续期检查失败", e);
        }
    }
    
    private Account getOrCreateAccount(Session session) throws Exception {
        KeyPair accountKeyPair = loadOrCreateAccountKeyPair();
        AccountBuilder accountBuilder = new AccountBuilder()
                .addContact("mailto:" + accountEmail)
                .agreeToTermsOfService()
                .useKeyPair(accountKeyPair);
        
        return accountBuilder.create(session);
    }
    
    private void processAuthorization(Authorization auth) throws Exception {
        Http01Challenge challenge = auth.findChallenge(Http01Challenge.TYPE);
        if (challenge == null) {
            throw new Exception("找不到HTTP-01验证方式");
        }
        
        try {
            // 保存验证内容
            challengeService.saveChallenge(challenge.getToken(), challenge.getAuthorization());
            
            // 触发验证
            challenge.trigger();
            
            // 等待验证完成
            while (auth.getStatus() != Status.VALID) {
                if (auth.getStatus() == Status.INVALID) {
                    throw new Exception("域名验证失败");
                }
                Thread.sleep(3000L);
                auth.update();
            }
            
            log.info("域名验证成功");
        } finally {
            // 清理验证内容
            challengeService.removeChallenge(challenge.getToken());
        }
    }
    
    private CertificateResult convertToResult(CertificateEntity entity) {
        return CertificateResult.builder()
                .domain(entity.getDomain())
                .certificatePem(entity.getCertificatePem())
                .privateKeyPem(entity.getPrivateKeyPem())
                .expirationTime(entity.getExpiresAt().toInstant(java.time.ZoneOffset.UTC).toEpochMilli())
                .build();
    }
    
    private KeyPair loadOrCreateAccountKeyPair() throws Exception {
        File accountKeyFile = new File(ACCOUNT_KEY_FILE);
        if (accountKeyFile.exists()) {
            try (FileReader fr = new FileReader(accountKeyFile)) {
                return KeyPairUtils.readKeyPair(fr);
            }
        }

        KeyPair keyPair = KeyPairUtils.createKeyPair(2048);
        try (FileWriter fw = new FileWriter(accountKeyFile)) {
            KeyPairUtils.writeKeyPair(keyPair, fw);
        }
        return keyPair;
    }
    
    private KeyPair generateOrLoadDomainKeyPair() throws Exception {
        File domainKeyFile = new File(DOMAIN_KEY_FILE);
        if (domainKeyFile.exists()) {
            try (FileReader fr = new FileReader(domainKeyFile)) {
                return KeyPairUtils.readKeyPair(fr);
            }
        }

        KeyPair keyPair = KeyPairUtils.createKeyPair(2048);
        try (FileWriter fw = new FileWriter(domainKeyFile)) {
            KeyPairUtils.writeKeyPair(keyPair, fw);
        }
        return keyPair;
    }
    
    // 其他辅助方法...
} 