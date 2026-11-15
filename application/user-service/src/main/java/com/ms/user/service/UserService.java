package com.ms.user.service;

import com.ms.user.dto.UserDTO;
import com.ms.user.entity.User;
import com.ms.user.exception.UserNotFoundException;
import com.ms.user.repository.UserRepository;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional(readOnly = true)
public class UserService {

    private static final Logger log = LoggerFactory.getLogger(UserService.class);

    private final UserRepository userRepository;
    private final Counter usersCreated;

    public UserService(UserRepository userRepository, MeterRegistry meterRegistry) {
        this.userRepository = userRepository;
        // Бизнес-метрика: сколько пользователей создано (счётчик users.created.total).
        this.usersCreated = Counter.builder("users.created")
                .description("Total number of users created")
                .register(meterRegistry);
    }

    public List<UserDTO> getAllUsers() {
        return userRepository.findAll().stream()
                .map(this::toDTO)
                .toList();
    }

    public UserDTO getUserById(Long id) {
        return userRepository.findById(id)
                .map(this::toDTO)
                .orElseThrow(() -> new UserNotFoundException("User not found with id: " + id));
    }

    @Transactional
    public UserDTO createUser(UserDTO userDTO) {
        User user = toEntity(userDTO);
        user = userRepository.save(user);
        usersCreated.increment();
        log.info("User created id={} name={}", user.getId(), user.getName());
        return toDTO(user);
    }

    @Transactional
    public UserDTO updateUser(Long id, UserDTO userDTO) {
        User user = userRepository.findById(id)
                .orElseThrow(() -> new UserNotFoundException("User not found with id: " + id));
        user.setName(userDTO.getName());
        user.setEmail(userDTO.getEmail());
        user = userRepository.save(user);
        log.info("User updated id={}", id);
        return toDTO(user);
    }

    @Transactional
    public void deleteUser(Long id) {
        User user = userRepository.findById(id)
                .orElseThrow(() -> new UserNotFoundException("User not found with id: " + id));
        userRepository.delete(user);
        log.info("User deleted id={}", id);
    }

    private UserDTO toDTO(User user) {
        return new UserDTO(user.getId(), user.getName(), user.getEmail());
    }

    private User toEntity(UserDTO userDTO) {
        User user = new User();
        user.setName(userDTO.getName());
        user.setEmail(userDTO.getEmail());
        return user;
    }
}
