package com.ms.client.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;

@Configuration
@EnableConfigurationProperties(UserServiceProperties.class)
public class RestClientConfig {

    private final UserServiceProperties properties;

    public RestClientConfig(UserServiceProperties properties) {
        this.properties = properties;
    }

    @Bean
    public RestClient restClient() {
        return RestClient.builder()
                .baseUrl(properties.getUrl())
                .build();
    }
}
