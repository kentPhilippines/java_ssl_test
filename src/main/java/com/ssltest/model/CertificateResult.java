package com.ssltest.model;

import lombok.Data;
import lombok.Builder;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import com.fasterxml.jackson.annotation.JsonIgnore;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CertificateResult {
    private String domain;
    private String certificatePem;
    private String privateKeyPem;
    private long expirationTime;
    
    @JsonIgnore
    public boolean isValid() {
        return expirationTime > System.currentTimeMillis();
    }
} 