package com.ssltest.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.util.concurrent.ConcurrentHashMap;

@Slf4j
@Service
@RestController
public class ChallengeService {
    
    private final ConcurrentHashMap<String, String> challengeTokens = new ConcurrentHashMap<>();
    
    public void saveChallenge(String token, String authorization) {
        log.info("保存验证令牌: {}", token);
        challengeTokens.put(token, authorization);
    }
    
    @GetMapping("/.well-known/acme-challenge/{token}")
    public ResponseEntity<String> getChallenge(@PathVariable String token) {
        String authorization = challengeTokens.get(token);
        if (authorization == null) {
            log.warn("未找到令牌对应的验证内容: {}", token);
            return ResponseEntity.notFound().build();
        }
        log.info("返回验证内容，令牌: {}", token);
        return ResponseEntity.ok()
                .contentType(MediaType.TEXT_PLAIN)
                .body(authorization);
    }
    
    public void removeChallenge(String token) {
        challengeTokens.remove(token);
        log.info("移除验证令牌: {}", token);
    }
} 