package com.ms.client.controller;

import com.ms.client.dto.UserDTO;
import com.ms.client.service.UserClientService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.HttpClientErrorException;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping()
public class UserProxyController {

    private final UserClientService userClientService;

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.status(HttpStatus.OK).body(Map.of("status", "OK"));
    }

    public UserProxyController(UserClientService userClientService) {
        this.userClientService = userClientService;
    }

    @GetMapping("/users")
    public List<UserDTO> getAllUsers() {
        return userClientService.getAllUsers();
    }

    @GetMapping("/users/{id}")
    public UserDTO getUserById(@PathVariable Long id) {
        return userClientService.getUserById(id);
    }

    @PostMapping("/users")
    public ResponseEntity<UserDTO> createUser(@RequestBody UserDTO userDTO) {
        UserDTO created = userClientService.createUser(userDTO);
        return ResponseEntity.status(HttpStatus.CREATED).body(created);
    }

    @PutMapping("/users/{id}")
    public UserDTO updateUser(@PathVariable Long id, @RequestBody UserDTO userDTO) {
        return userClientService.updateUser(id, userDTO);
    }

    @DeleteMapping("/users/{id}")
    public ResponseEntity<Void> deleteUser(@PathVariable Long id) {
        return userClientService.deleteUser(id);
    }

    @ExceptionHandler(HttpClientErrorException.NotFound.class)
    public ResponseEntity<Map<String, String>> handleNotFound(HttpClientErrorException.NotFound ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(Map.of("error", "User not found"));
    }

    @ExceptionHandler(HttpClientErrorException.BadRequest.class)
    public ResponseEntity<Map<String, String>> handleBadRequest(HttpClientErrorException.BadRequest ex) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(Map.of("error", ex.getMessage()));
    }

    @ExceptionHandler(HttpClientErrorException.class)
    public ResponseEntity<Map<String, String>> handleClientError(HttpClientErrorException ex) {
        return ResponseEntity.status(ex.getStatusCode())
                .body(Map.of("error", ex.getMessage()));
    }
}
