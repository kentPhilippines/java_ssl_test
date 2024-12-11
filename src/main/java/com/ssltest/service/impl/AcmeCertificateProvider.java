package com.ssltest.service.impl;

import com.ssltest.entity.CertificateEntity;
import com.ssltest.model.CertificateResult;
import com.ssltest.repository.CertificateRepository;
import com.ssltest.service.CertificateProvider;
import com.ssltest.service.ChallengeService;
import lombok.extern.slf4j.Slf4j;
import org.shredzone.acme4j.*;
import org.shredzone.acme4j.challenge.Http01Challenge;
import org.shredzone.acme4j.util.CSRBuilder;
import org.shredzone.acme4j.util.KeyPairUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.io.*;
import java.security.KeyPair;
import java.security.PrivateKey;
import java.security.cert.X509Certificate;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.List;

import org.bouncycastle.openssl.jcajce.JcaPEMWriter;
import org.bouncycastle.util.io.pem.PemObject;
import org.bouncycastle.util.io.pem.PemWriter;

@Slf4j
@Service
public class AcmeCertificateProvider implements CertificateProvider {
    
    @Value("${acme.server.url:https://acme-staging-v02.api.letsencrypt.org/directory}")
    private String acmeServerUrl;
    
    @Value("${acme.account.email:admin@example.com}")
    private String accountEmail;
    
    @Value("${acme.client.renewal-days:30}")
    private int renewalDays;
    
    @Value("${acme.client.notify-days:7}")
    private int notifyDays;
    
    @Value("${acme.client.auto-renewal:true}")
    private boolean autoRenewal;
    
    @Value("${acme.client.ocsp-check-hours:24}")
    private int ocspCheckHours;
    
    @Value("${acme.challenge.type:HTTP-01}")
    private String challengeType;
    
    @Value("${acme.challenge.http-port:80}")
    private int challengeHttpPort;
    
    @Value("${acme.challenge.timeout:180}")
    private int challengeTimeout;
    
    @Value("${acme.challenge.retries:3}")
    private int challengeRetries;
    
    @Value("${acme.challenge.retry-interval:10}")
    private int challengeRetryInterval;
    
    @Value("${acme.storage.path:${user.home}/.acme}")
    private String storagePath;
    
    @Autowired
    private CertificateRepository certificateRepository;

    
    @Autowired
    private ChallengeService challengeService;
    
    private static final String ACCOUNT_KEY_FILE = "account.key";
    private static final String DOMAIN_KEY_FILE = "domain.key";

    @PostConstruct
    public void init() {
        File sslDir = new File(storagePath);
        if (!sslDir.exists()) {
            sslDir.mkdirs();
        }
        log.info("ACME配置初始化完成:");
        log.info("服务器URL: {}", acmeServerUrl);
        log.info("账户邮箱: {}", accountEmail);
        log.info("存储路径: {}", storagePath);
        log.info("自动更新: {}", autoRenewal);
        log.info("更新天数: {}", renewalDays);
        log.info("通知天数: {}", notifyDays);
        log.info("验证类型: {}", challengeType);
    }

    @Override
    public CertificateResult applyCertificate(String domain) throws Exception {
        log.info("开始为域名{}申请证书", domain);
        
        // 检查是否已有有效证书
        CertificateEntity existingCert = certificateRepository.findByDomain(domain);
        if (existingCert != null && 
            existingCert.getExpiresAt().isAfter(LocalDateTime.now().plusDays(renewalDays))) {
            log.info("域名{}已有有效证书", domain);
            return convertToResult(existingCert);
        }
        
        try {
            Session session = new Session(acmeServerUrl);
            Account account = getOrCreateAccount(session);
            KeyPair domainKeyPair = generateOrLoadDomainKeyPair();
            
            // 申请证书
            Order order = account.newOrder().domains(domain).create();
            
            // 域名验证
            for (Authorization auth : order.getAuthorizations()) {
                processAuthorization(auth);
            }
            
            // 生成CSR并完成订单
            CSRBuilder csrb = new CSRBuilder();
            csrb.addDomain(domain);
            csrb.sign(domainKeyPair);
            
            order.execute(csrb.getEncoded());
            Certificate certificate = order.getCertificate();
            
            // 保存证书
            CertificateEntity certEntity = saveCertificate(domain, certificate, domainKeyPair, account);
            
            return convertToResult(certEntity);
            
        } catch (Exception e) {
            log.error("证书申请失败: {}", e.getMessage(), e);
            throw new RuntimeException("证书申请失败: " + e.getMessage(), e);
        }
    }
    
    @Scheduled(cron = "0 0 0 * * ?") // 每天凌晨执行
    public void renewCertificates() {
        log.info("开始检查证书期");
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
            challengeService.saveChallenge(challenge.getToken(), challenge.getAuthorization());
            challenge.trigger();
            
            int attempts = 0;
            while (auth.getStatus() != Status.VALID && attempts < 10) {
                if (auth.getStatus() == Status.INVALID) {
                    throw new Exception("域名验证失败");
                }
                Thread.sleep(3000L);
                auth.update();
                attempts++;
            }
            
            if (auth.getStatus() != Status.VALID) {
                throw new Exception("域名验证超时");
            }
            
            log.info("域名验证成功");
        } catch (Exception e) {
            log.error("域名验证失败: {}", e.getMessage());
            throw e;
        } finally {
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
    
    private CertificateEntity saveCertificate(String domain, Certificate certificate, KeyPair domainKeyPair, Account account) throws Exception {
        // 获取证书并转换为PEM格式
        X509Certificate x509Cert = certificate.getCertificate();
        StringWriter writer = new StringWriter();
        try (PemWriter pemWriter = new PemWriter(writer)) {
            pemWriter.writeObject(new PemObject("CERTIFICATE", x509Cert.getEncoded()));
        }
        String certificatePem = writer.toString();
        
        // 获取私钥PEM
        StringWriter privateKeyWriter = new StringWriter();
        try (PemWriter pemWriter = new PemWriter(privateKeyWriter)) {
            pemWriter.writeObject(new PemObject("PRIVATE KEY", domainKeyPair.getPrivate().getEncoded()));
        }
        String privateKeyPem = privateKeyWriter.toString();

        // 验证证书格式
        if (!certificatePem.contains("BEGIN CERTIFICATE") || !privateKeyPem.contains("BEGIN PRIVATE KEY")) {
            throw new IllegalStateException("无效的证书或私钥格式");
        }
        
        // 构建证书实体
        CertificateEntity certEntity = CertificateEntity.builder()
                .domain(domain)
                .certificatePem(certificatePem)
                .privateKeyPem(privateKeyPem)
                .issuedAt(LocalDateTime.now())
                .expiresAt(LocalDateTime.now().plusDays(90))
                .status("ACTIVE")
                .acmeAccountUrl(account.getLocation().toString())
                .build();
        
        try {
            return certificateRepository.save(certEntity);
        } catch (Exception e) {
            log.error("保存证书信息失败: {}", e.getMessage());
            throw new RuntimeException("保存证书失败", e);
        }
    }
    
    // 其他辅助方法...
} 