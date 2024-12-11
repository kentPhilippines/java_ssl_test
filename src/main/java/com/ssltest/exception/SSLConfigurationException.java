package com.ssltest.exception;

public class SSLConfigurationException extends RuntimeException {
    public SSLConfigurationException(String message) {
        super(message);
    }
    
    public SSLConfigurationException(String message, Throwable cause) {
        super(message, cause);
    }
} 