package com.ssltest.repository;

import com.ssltest.entity.CertificateEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import java.time.LocalDateTime;
import java.util.List;

public interface CertificateRepository extends JpaRepository<CertificateEntity, Long> {
    CertificateEntity findByDomain(String domain);
    List<CertificateEntity> findByExpiresAtBeforeAndStatus(LocalDateTime dateTime, String status);
} 