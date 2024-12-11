package com.ssltest.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Bean;

import javax.annotation.PostConstruct;
import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

@Slf4j
@Configuration
public class AcmeConfig {
    
    @Value("${acme.challenge.path}")
    private String challengePath;
    
    @PostConstruct
    public void init() {
        try {
            Path path = Paths.get(challengePath);
            if (!Files.exists(path)) {
                Files.createDirectories(path);
            }
            // 确保目录权限正确
            File challengeDir = path.toFile();
            challengeDir.setReadable(true, false);
            challengeDir.setExecutable(true, false);
            log.info("ACME challenge目录已创建: {}", challengePath);
        } catch (Exception e) {
            log.error("创建ACME challenge目录失败", e);
            throw new RuntimeException("无法创建challenge目录", e);
        }
    }
} 