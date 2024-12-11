package com.ssltest.config;

import lombok.extern.slf4j.Slf4j;
import org.apache.catalina.connector.Connector;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.embedded.tomcat.TomcatServletWebServerFactory;
import org.springframework.boot.web.server.WebServerFactoryCustomizer;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Component;

@Slf4j
@Configuration
@Component
public class DynamicSSLConfig implements WebServerFactoryCustomizer<TomcatServletWebServerFactory> {
    
    @Value("${server.http.port:80}")
    private int httpPort;
    
    @Value("${server.port:8443}")
    private int httpsPort;

    @Override
    public void customize(TomcatServletWebServerFactory factory) {
        // 配置HTTP连接器（用于ACME验证）
        Connector connector = new Connector(TomcatServletWebServerFactory.DEFAULT_PROTOCOL);
        connector.setPort(httpPort);
        connector.setSecure(false);
        connector.setScheme("http");
        
        // 对于非验证请求，重定向到HTTPS
        connector.setRedirectPort(httpsPort);
        
        factory.addAdditionalTomcatConnectors(connector);
    }
} 