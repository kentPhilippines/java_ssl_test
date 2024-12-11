package com.ssltest.entity;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import javax.persistence.*;
import java.time.LocalDateTime;

@Data
@Entity
@Table(name = "certificates")
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CertificateEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(unique = true, nullable = false)
    private String domain;
    
    @Column(columnDefinition = "TEXT")
    private String certificatePem;
    
    @Column(columnDefinition = "TEXT")
    private String privateKeyPem;
    
    @Column(nullable = false)
    private LocalDateTime issuedAt;
    
    @Column(nullable = false)
    private LocalDateTime expiresAt;
    
    @Column(length = 20)
    private String status;
    
    @Column(length = 512)
    private String acmeAccountUrl;
} 