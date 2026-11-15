package com.ms.client.service;

import com.ms.client.dto.UserDTO;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.util.List;

@Service
public class UserClientService {

    private static final Logger log = LoggerFactory.getLogger(UserClientService.class);

    private final RestClient restClient;
    private final Counter proxyRequests;

    public UserClientService(RestClient restClient, MeterRegistry meterRegistry) {
        this.restClient = restClient;
        // Бизнес-метрика: число проксированных запросов в user-service.
        this.proxyRequests = Counter.builder("proxy.user.requests")
                .description("Total proxied requests to user-service")
                .register(meterRegistry);
    }

    public List<UserDTO> getAllUsers() {
        proxyRequests.increment();
        log.info("Proxy GET /users");
        return restClient.get()
                .uri("/users")
                .retrieve()
                .body(new ParameterizedTypeReference<List<UserDTO>>() {
                });
    }

    public UserDTO getUserById(Long id) {
        return restClient.get()
                .uri("/users/{id}", id)
                .retrieve()
                .body(UserDTO.class);
    }

    public UserDTO createUser(UserDTO userDTO) {
        return restClient.post()
                .uri("/users")
                .body(userDTO)
                .retrieve()
                .body(UserDTO.class);
    }

    public UserDTO updateUser(Long id, UserDTO userDTO) {
        return restClient.put()
                .uri("/users/{id}", id)
                .body(userDTO)
                .retrieve()
                .body(UserDTO.class);
    }

    public ResponseEntity<Void> deleteUser(Long id) {
        return restClient.delete()
                .uri("/users/{id}", id)
                .retrieve()
                .toBodilessEntity();
    }
}
