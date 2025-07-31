package com.xiilab.keycloak.spi;

import org.keycloak.events.Event;
import org.keycloak.events.EventListenerProvider;
import org.keycloak.events.EventType;
import org.keycloak.events.admin.AdminEvent;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.UserModel;

import java.util.Arrays;
import java.util.List;

public class AstragoEventListenerProvider implements EventListenerProvider {
    
    private final KeycloakSession session;

    public AstragoEventListenerProvider(KeycloakSession session) {
        this.session = session;
    }

    @Override
    public void onEvent(Event event) {
        System.out.println("=== Astrago SPI Event Triggered ===");
        System.out.println("Event Type: " + event.getType());
        System.out.println("User ID: " + event.getUserId());
        System.out.println("Realm: " + event.getRealmId());
        
        // LDAP 사용자 연동 시점과 로그인 시점에 실행
        if (event.getType() == EventType.LOGIN || 
            event.getType() == EventType.REGISTER) {
            
            System.out.println("=== Processing LOGIN/REGISTER Event ===");
            
            String userId = event.getUserId();
            if (userId != null) {
                UserModel user = session.users().getUserById(session.getContext().getRealm(), userId);
                if (user != null) {
                    System.out.println("User found: " + user.getUsername());
                    System.out.println("Federation Link: " + user.getFederationLink());
                    
                    // LDAP 사용자인지 확인 (federationLink가 있으면 LDAP 사용자)
                    if (user.getFederationLink() != null) {
                        System.out.println("=== LDAP User Detected - Adding Attributes ===");
                        
                        // 속성이 이미 있는지 확인하고 없으면 추가
                        if (user.getAttributes().get("workspaceCreateLimit") == null || user.getAttributes().get("workspaceCreateLimit").isEmpty()) {
                            user.setAttribute("workspaceCreateLimit", Arrays.asList("2"));
                            System.out.println("Added workspaceCreateLimit=2");
                        } else {
                            System.out.println("workspaceCreateLimit already exists: " + user.getAttributes().get("workspaceCreateLimit"));
                        }
                        
                        if (user.getAttributes().get("signUpPath") == null || user.getAttributes().get("signUpPath").isEmpty()) {
                            user.setAttribute("signUpPath", Arrays.asList("ASTRAGO"));
                            System.out.println("Added signUpPath=ASTRAGO");
                        } else {
                            System.out.println("signUpPath already exists: " + user.getAttributes().get("signUpPath"));
                        }
                        
                        if (user.getAttributes().get("approvalYN") == null || user.getAttributes().get("approvalYN").isEmpty()) {
                            user.setAttribute("approvalYN", Arrays.asList("true"));
                            System.out.println("Added approvalYN=true");
                        } else {
                            System.out.println("approvalYN already exists: " + user.getAttributes().get("approvalYN"));
                        }
                    } else {
                        System.out.println("User is not LDAP federated, skipping attribute addition");
                    }
                } else {
                    System.out.println("User not found for ID: " + userId);
                }
            } else {
                System.out.println("User ID is null");
            }
        } else {
            System.out.println("Event type not LOGIN or REGISTER, skipping");
        }
        
        System.out.println("=== Astrago SPI Event Processing Complete ===");
    }

    @Override
    public void onEvent(AdminEvent event, boolean includeRepresentation) {
        // Admin 이벤트는 처리하지 않음
    }

    @Override
    public void close() {
        // Nothing to close
    }
} 