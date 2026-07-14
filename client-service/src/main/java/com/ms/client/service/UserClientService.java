package com.ms.client.service;

import com.ms.client.dto.UserDTO;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.util.List;

@Service
public class UserClientService {

    private final RestClient restClient;

    public UserClientService(RestClient restClient) {
        this.restClient = restClient;
    }

    public List<UserDTO> getAllUsers() {
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
