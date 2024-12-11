package com.ssltest.service.impl;

import com.ssltest.service.CertificateProvider;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Primary;
import org.springframework.retry.annotation.Backoff;
import org.springframework.retry.annotation.Retryable;
import org.springframework.stereotype.Service;
import com.ssltest.model.CertificateResult;

@Slf4j
@Service
@Primary
public class RetryableAcmeCertificateProvider implements CertificateProvider {

    @Autowired
    private AcmeCertificateProvider delegate;

    @Override
    @Retryable(
        value = {Exception.class},
        maxAttempts = 3,
        backoff = @Backoff(delay = 5000, multiplier = 2)
    )
    public CertificateResult applyCertificate(String domain) throws Exception {
        return delegate.applyCertificate(domain);
    }
} 