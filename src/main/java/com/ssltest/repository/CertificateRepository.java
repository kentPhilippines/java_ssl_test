package com.ssltest.repository;
import com.ssltest.entity.CertificateEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface CertificateRepository extends JpaRepository<CertificateEntity, Long> {
    CertificateEntity findByDomain(String domain);
    
    List<CertificateEntity> findByExpiresAtBeforeAndStatus(LocalDateTime date, String status);
    
    @Modifying
    @Query("UPDATE CertificateEntity c SET c.status = :status WHERE c.domain = :domain")
    int updateStatus(@Param("domain") String domain, @Param("status") String status);
} 