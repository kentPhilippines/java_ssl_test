package com.ssltest.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;

@Slf4j
@Service
public class AlertService {
    
    @Value("${alert.email.to}")
    private String alertEmail;
    
    private final JavaMailSender mailSender;
    
    public AlertService(JavaMailSender mailSender) {
        this.mailSender = mailSender;
    }
    
    public void sendAlert(String subject, String message) {
        try {
            SimpleMailMessage mailMessage = new SimpleMailMessage();
            mailMessage.setTo(alertEmail);
            mailMessage.setSubject(subject);
            mailMessage.setText(message);
            mailSender.send(mailMessage);
            log.info("告警邮件已发送: {}", subject);
        } catch (Exception e) {
            log.error("发送告警邮件失败", e);
        }
    }
} 