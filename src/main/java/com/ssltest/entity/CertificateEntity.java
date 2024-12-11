package com.ssltest.entity;

import lombok.Data;
import javax.persistence.*;
import java.time.LocalDateTime;

@Data
@Entity
@Table(name = "certificates")
public class CertificateEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    private String domain;
    private String certificatePem;
    private String privateKeyPem;
    private LocalDateTime issuedAt;
    private LocalDateTime expiresAt;
    private String status;  // ACTIVE, EXPIRED, REVOKED
    
    @Column(name = "acme_account_url")
    private String acmeAccountUrl;
    
    @Column(name = "last_renewal_attempt")
    private LocalDateTime lastRenewalAttempt;
} 